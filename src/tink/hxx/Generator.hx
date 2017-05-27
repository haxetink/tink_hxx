package tink.hxx;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.macro.Positions;

using haxe.macro.Tools;
using StringTools;
using tink.MacroApi;
using tink.CoreApi;

typedef GeneratorOptions = {
  var child(default, null):ComplexType;
  @:optional var customAttributes(default, null):String;
  @:optional var flatten(default, null):Expr->Expr;
  @:optional var merger(default, null):Expr;
  @:optional var instantiate(default, null):Instantiation->Option<Expr>;
}

typedef Instantiation = {
  var name(default, null):StringAt;
  var attr(default, null):Expr;
  var children(default, null):Option<Expr>;
  var type(default, null):Type;
}

@:forward
abstract Generator(GeneratorObject) from GeneratorObject to GeneratorObject {
  @:from static function ofFunction(f:StringAt->Expr->Option<Expr>->Expr):Generator {
    return new SimpleGenerator(Positions.sanitize(null), f);
  }
  
  @:from static function fromOptions(options:GeneratorOptions):Generator {
    
    var merger = switch options.merger {
      case null: macro tink.hxx.Merge.objects;
      case v: v;
    }

    function get<V>(o:{ var flatten(default, null): V; }) return o.flatten;

    var flatten = 
      if (Reflect.field(options, 'flatten') == null) {
        var call = (options.child.toType().sure().getID() + '.flatten').resolve();
        function (e:Expr) return macro @:pos(e.pos) $call($e);
      }
      else
        options.flatten;

    var instantiate =
      if (Reflect.field(options, 'instantiate') == null) 
        function (_) return None;
      else
        options.instantiate;
    
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
                        case macro $call($merge(${{ expr: EObjectDecl(forbidden) }})):
                          var name = call.getIdent().sure();
                          call.reject('Empty node <$name /> found where complex property was expected');
                        case macro $call($merge($a{args}), $children):
                          var name = call.getIdent().sure();
                          
                          switch args[0] {
                            case { expr: EObjectDecl([]) }:
                            case { expr: EObjectDecl(forbidden) } :
                              forbidden[0].expr.reject('node <$name> is assumed to be a complex property and therefore cannot have attributes of its own');
                            default:
                              throw 'assert';
                          }
                          
                          var args:Array<FunctionArg> = [for (e in args.slice(1)) {
                            name: e.getIdent().sure(),
                            type: null
                          }];
                          
                          fields.push({
                            field: name,
                            expr: 
                              switch args {
                                case []:
                                  macro @:pos(children.pos) tink.hxx.Merge.complexAttribute(${flatten(children)});
                                default: 
                                  EFunction(null, { 
                                    ret: null,
                                    args: args,
                                    expr: macro @:pos(call.pos) return ${flatten(children)}
                                  }).at(call.pos);
                              }
                          });
                          
                        case { expr: ENew(_, _) } :
                          c.reject('Assuming complex property here, but got instantiation instead');
                        default:
                          trace(c.toString());
                          throw 'assert';
                      }
                    [Generator.applySpreads(attr, options.customAttributes, merger)];
                  default:
                    throw 'assert';
                }
              case [false, _] | [_ , None]:
                [Generator.applySpreads(attr, options.customAttributes, merger)].concat(coerce(children).toArray());
              default:
                throw 'assert';
            }
                    
        return
          switch Context.parseInlineString(name.value, name.pos) {
            case macro super:
              var ctor = 
                try
                  Context.getLocalClass().get().superClass.t.get().constructor.get()
                catch (e:Dynamic) 
                  name.pos.error('Invalid call to super');
                
              // name.pos.error(ctor);
              macro @:pos(name.pos) super($a{getArgs(shouldFlatten(ctor.type, name))});
              // throw 'whaaa?';
            case macro $i{cls}, macro $_.$cls if (cls.charAt(0).toLowerCase() != cls.charAt(0)):
              
              switch name.value.definedType() {
                case None: name.pos.error('Unknown type ${name.value}');
                case Some(_.reduce() => t):
                  switch instantiate({ name: name, attr: attr, children: children, type: t }) {
                    case Some(v): v;
                    case None:
                      var ctor = switch t {
                        case TInst(_.get() => cl, _):
                          var ctor = cl.constructor;
                          while(ctor == null && cl.superClass != null) {
                            cl = cl.superClass.t.get();
                            ctor = cl.constructor;
                          }
                          if (ctor == null)
                            throw 'Class ${name.value} has no constructor';
                          ctor.get().type;
                        case TAbstract(_.get().impl.get() => cl, _):
                          var ret = null;
                          for (f in cl.statics.get()) 
                            if (f.name == '_new') {
                              ret = f;
                              break;
                            }
                          if (ret == null)
                            throw 'Abstract ${name.value} has no constructor';
                          ret.type;
                        default:
                          throw '${name.value} is neither class nor abstract';
                      }

                      name.value.instantiate(getArgs(shouldFlatten(ctor, name)), name.pos);
                  }
              }
              
            
            case call: macro @:pos(name.pos) $call($a{getArgs(false)});
          }
        
      }
    );
    return gen;
  } 

  static function shouldFlatten(f:Type, name:StringAt)
    return 
      switch f.reduce() {
        case TFun([tAttr, tChildren], _): false;
        case TFun([tAttr], _): true;
        default:
          name.pos.error('${name.value} does not seem suitable for HXX');
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
  
  static public function applySpreads(attr:Expr, ?customAttributes:String, merger:Expr, ?postprocess) 
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
            
          if (postprocess != null)
            postprocess(std);
          splats.unshift({ expr: EObjectDecl(std), pos: attr.pos });
          attr = macro @:pos(attr.pos) $merger($a{splats});
        default: throw 'assert';
      }    
}

interface GeneratorObject { 
  function string(s:StringAt):Option<Expr>;
  function flatten(pos:Position, children:Array<Expr>):Expr;
  function makeNode(name:StringAt, attributes:Array<Attribute>, children:Array<Expr>):Expr;
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
  
  function reserved(name:StringAt) 
    return switch name.value {
      case 'class': 'className';
      case v: v;
    }

  public function makeNode(name:StringAt, attributes:Array<Attribute>, children:Array<Expr>):Expr     
    return doMakeNode(
      name,
      EObjectDecl([for (a in attributes) switch a {
        case Splat(e): { field: '...', expr: e };
        case Empty(name): { field: reserved(name), expr: macro @:pos(name.pos) true };
        case Regular(name, value): { field: reserved(name), expr: interpolate(value) };
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
