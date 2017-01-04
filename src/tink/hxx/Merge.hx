package tink.hxx;

#if macro
import haxe.Constraints.IMap;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Context;
using haxe.macro.Tools;
using tink.MacroApi;

typedef Lookup = {
  function get(key:String):Type;
  function remove(key:String):Bool;
}
#end

class Merge {

  macro static public function objects(primary:Expr, rest:Array<Expr>) {
    function combine(expected:Lookup) {
      var result = [],
          vars = [];
      
      if (false) {
        EVars(vars);
        EObjectDecl(result);
      }
      function addField(name:String, expr:Expr) {
        var ct = expected.get(name).toComplex();
        result.push({ field: name, expr: macro @:pos(expr.pos) ($expr : $ct) });
        expected.remove(name);
      }
      switch primary.expr {
        case EObjectDecl(given):
          for (f in given)
            switch expected.get(f.field) {
              case null:
                f.expr.reject('invalid field ${f.field}');
              default:
                addField(f.field, f.expr);
            }
        default: 
          throw 'assert';
      }
      
      for (o in rest) {
        var vName = '__' + vars.length;
        
        vars.push({
          type: null, name: vName, expr: o,
        });
        
        for (f in o.typeof().sure().getFields().sure()) 
          switch expected.get(f.name) {
            case null:
            default:
              var name = f.name;
              addField(name, macro $i{vName}.$name);
          }
      }
      
      return [
        EVars(vars).at(),
        EObjectDecl(result).at(),
      ].toBlock();      
    }
    return switch Context.getExpectedType() {
      case null: throw 'unknown';
      case v: 
        switch v.follow() {
          case TAnonymous([for (f in _.get().fields) f.name => f.type] => expected): 
            combine(expected);
          case TDynamic(v):
            var removed = new Map();
            combine({
              get: function (name) return if (removed[name]) null else v,
              remove: function (name) return !removed[name] && (removed[name] = true),
            });
            //throw v;
          case v: 
            throw v.toString();
        }
    }
  }
    
}

