package hxx;

import haxe.macro.Context;
import haxe.macro.Expr;
import tink.macro.Positions;

using haxe.macro.Tools;
using StringTools;
using tink.MacroApi;
using tink.CoreApi;

@:forward
abstract Generator(GeneratorObject) from GeneratorObject to GeneratorObject {
  @:from static function ofFunction(f:StringAt->Expr->Option<Expr>->Expr):Generator {
    return new SimpleGenerator(Positions.sanitize(null), f);
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
  
  static public function applySplats(attr:Expr, ?customAttributes:String) 
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
          attr = macro @:pos(attr.pos) hxx.Merge.objects($a{splats});
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