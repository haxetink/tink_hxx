package tink.hxx;

import haxe.macro.Context;
import haxe.macro.Expr;
import tink.macro.Positions;

using haxe.macro.Tools;
using StringTools;
using tink.MacroApi;
using tink.CoreApi;

typedef GeneratorOptions = {
  var child(default, null):ComplexType;
  @:optional var customAttributes(default, null):String;
  @:optional var flatten(default, null):Expr->Expr;
}

@:forward
abstract Generator(GeneratorObject) from GeneratorObject to GeneratorObject {
  @:from static function ofFunction(f:StringAt->Expr->Option<Expr>->Expr):Generator {
    return new SimpleGenerator(Positions.sanitize(null), f);
  }
  
  @:from static function fromOptions(options:GeneratorOptions):Generator {
    function get<V>(o:{ var flatten(default, null): V; }) return o.flatten;
    var flatten = 
      if (null == get(options)) {
        var call = (options.child.toType().sure().getID() + '.flatten').resolve();
        function (e:Expr) return macro @:pos(e.pos) $call($e);
      }
      else
        options.flatten;
    
    function coerce(children:Option<Expr>) 
      return 
        switch options.child {
          case null: children;
          case ct:
            children.map(function (e) return switch e {
              case macro $a{children}:
                return {
                  pos: e.pos,
                  expr: EArrayDecl(
                    [for (c in children) switch c {
                      case macro for ($head) $body: c;
                      default: macro @:pos(c.pos) ($c : $ct);
                    }]
                  )
                }
              case v: Context.fatalError('Cannot generate ${v.toString()}', v.pos);      
            });
        }
    
    
    var gen:GeneratorObject = new SimpleGenerator(
      Positions.sanitize(null),    
      function (name:StringAt, attr:Expr, children:Option<Expr>) {
              
        if (name.value == '...')           
          return 
            flatten(switch coerce(children) {
              case Some(v): v;
              default: macro [];
            });
        
        function getArgs(childrenAsArgs:Bool) 
          return 
            switch [childrenAsArgs, children] {
              case [true, Some(macro $a{children})]:
                switch attr.expr {
                  case EObjectDecl(fields):
                    for (c in children) 
                      switch c {
                        case macro $call($merge(${{ expr: EObjectDecl(forbidden) }}), $children):
                          var name = call.getIdent().sure();
                          
                          switch forbidden[0] {
                            case null:
                            case f:
                              f.expr.reject('node <$name> is assumed to be an attribute and therefore cannot have attributes of its own');
                          }
                          
                          fields.push({
                            field: name,
                            expr: macro @:pos(children.pos) tink.hxx.Merge.complexAttribute(${flatten(children)}),
                          });
                        default:
                          throw 'assert';
                      }
                    [Generator.applySpreads(attr, options.customAttributes)];
                  default:
                    throw 'assert';
                }
              case [false, _] | [_ , None]:
                [Generator.applySpreads(attr, options.customAttributes)].concat(coerce(children).toArray());
              default:
                throw 'assert';
            }
                    
        return
          switch Context.parseInlineString(name.value, name.pos) {
            case macro $i{cls}, macro $_.$cls if (cls.charAt(0).toLowerCase() != cls.charAt(0)):
              
              var cls = Context.getType(name.value).getClass();
                
              if (cls.constructor == null)
                name.pos.error('Class ${name.value} has no constructor');
                
              var flatten = 
                switch cls.constructor.get().type.reduce() {
                  case TFun([tAttr, tChildren], _): false;
                  case TFun([tAttr], _): true;
                  default:
                    name.pos.error('Constructor of ${name.value} does not seem suitable for HXX');
                }
                
              name.value.instantiate(getArgs(flatten), name.pos);
            
            case call: macro @:pos(name.pos) $call($a{getArgs(false)});
          }
        
      }
    );
    return gen;
  } 
  
  static public function trimString(s:String) {
    
    var pos = 0,
        max = s.length,
        leftNewline = false,
        rightNewline = false;

    while (pos < max) {
      switch s.charCodeAt(pos) {
        case '\n'.code | '\r'.code: leftNewline = true;
        case v:
          if (v > 32) break;
      }
      pos++;
    }
    
    while (max > pos) {
      switch s.charCodeAt(max-1) {
        case '\n'.code | '\r'.code: rightNewline = true;
        case v:
          if (v > 32) break;
      }
      max--;
    }
        
    if (!leftNewline) 
      pos = 0;
    if (!rightNewline)
      max = s.length;
      
    return s.substring(pos, max);
  }
  
  static public function applySpreads(attr:Expr, ?customAttributes:String) 
    return
      switch attr.expr {
        case EObjectDecl(fields):
          var ext = [],
              std = [],
              splats = [];
              
          for (f in fields)
            switch f.field {
              case '...': splats.push(f.expr);
              case _.indexOf('-') => -1: std.push(f);
              default: 
                if (customAttributes == null)
                  f.expr.reject('invalid field ${f.field}');
                else
                  ext.push(f);
            }
            
          if (ext.length > 0)
            std.push({
              field: customAttributes,
              expr: { expr: EObjectDecl(ext), pos: attr.pos },
            });
            
          splats.unshift({ expr: EObjectDecl(std), pos: attr.pos });
          attr = macro @:pos(attr.pos) tink.hxx.Merge.objects($a{splats});
        default: throw 'assert';
      }    
}

interface GeneratorObject { 
  function string(s:StringAt):Option<Expr>;
  function flatten(pos:Position, children:Array<Expr>):Expr;
  function makeNode(name:StringAt, attributes:Array<NamedWith<StringAt, Expr>>, children:Array<Expr>):Expr;
  function root(children:Array<Expr>):Expr;
}

class SimpleGenerator implements GeneratorObject { 
  var pos:Position;
  var doMakeNode:StringAt->Expr->Option<Expr>->Expr;
  public function new(pos, doMakeNode) {
    this.pos = pos;
    this.doMakeNode = doMakeNode;
  }
  
  public function string(s:StringAt) 
    return switch Generator.trimString(s.value) {
      case '': None;
      case v: Some(macro @:pos(s.pos) $v{v});
    }    
    
  function interpolate(e:Expr)
    return switch e {
      case { expr: EConst(CString(v)), pos: pos }:
        v.formatString(pos);
      case v: v;
    };
    
  public function flatten(pos:Position, children:Array<Expr>):Expr
    return makeNode({ pos: pos, value: '...' }, [], children);
  
  public function makeNode(name:StringAt, attributes:Array<NamedWith<StringAt, Expr>>, children:Array<Expr>):Expr     
    return doMakeNode(
      name,
      EObjectDecl([for (a in attributes) {
        field: switch a.name.value {
          case 'class': 'className';
          case v: v;
        },
        expr: interpolate(a.value),
      }]).at(name.pos),
      switch children {
        case null | []: None;
        case v: Some(EArrayDecl(v.map(interpolate)).at(name.pos));
      }
    );
  
  public function root(children:Array<Expr>):Expr 
    return
      switch children {
        case []: Context.fatalError('empty tree', pos);
        case [v]: v;
        case v: macro @:pos(pos) [$a{v}];
      }
  
}