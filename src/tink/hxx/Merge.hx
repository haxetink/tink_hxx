package tink.hxx;

#if macro
import haxe.Constraints.IMap;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Context;
using haxe.macro.Tools;
using tink.MacroApi;

typedef Lookup = {
  function get(key:String):{ optional:Bool, type:Type };
  function remove(key:String):Bool;
  function keys():Iterator<String>;
}
#end

class Merge {
  
  macro static public function complexAttribute(e:Expr) {
    return
      switch Context.getExpectedType().reduce() {
        case null:
          throw 'assert';
        case TFun([{ t: t }], _):
          var ct = t.toComplex();
          var before = switch [t.getID(), t.getFields()] {
            case ['Array' | 'String', _]: macro { };//TODO: handle maps as well
            case [_, Success(f)]:
              EVars([for (f in f) if (f.isPublic) {
                type: null,
                name: f.name,
                expr: '__data__.${f.name}'.resolve(),
              }]).at(e.pos);
            default:
              macro { };
          }
          return macro function (__data__:$ct) {
            $before;
            return $e;
          }
          
        case v:
          e;
      }
  }

  macro static public function objects(primary:Expr, rest:Array<Expr>) {
    
    function combine(type:Type, expected:Lookup) {
      var result = [],
          vars = [];
      
      if (false) {
        EVars(vars);
        EObjectDecl(result);
      }
      function addField(name:String, expr:Expr) {
        var ct = expected.get(name).type.toComplex();
        result.push({ field: name, expr: macro @:pos(expr.pos) ($expr : $ct) });
        expected.remove(name);
      }
      switch primary.expr {
        case EObjectDecl([]) if (rest.length == 1):
          var ct = type.toComplex();
          return macro @:pos(rest[0].pos) (${rest[0]} : $ct);
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
      
      var missing = [
        for (left in expected.keys()) if (!expected.get(left).optional) left
      ];
      
      switch missing {
        case []:
        case v: primary.reject('missing fields: ' + missing.join(', '));
      }
      
      return [
        EVars(vars).at(),
        EObjectDecl(result).at(),
      ].toBlock();      
    }
    
    return switch Context.getExpectedType() {
      case null: 
        primary.pos.error('unable to determine expected object type');
      case v: 
        function merge(expectedType:Type):Expr
          return 
            switch expectedType.follow() {
              case TAnonymous([for (f in _.get().fields) f.name => { type: f.type, optional: f.meta.has(':optional') } ] => expected): 
                combine(expectedType, expected);
              case TDynamic(v):
                var removed = new Map();
                combine(expectedType, {
                  get: function (name) return if (removed[name]) null else { optional: false, type: v },
                  remove: function (name) return !removed[name] && (removed[name] = true),
                  keys: function () return [].iterator(),
                });
              case TAbstract(_.get() => { pack: ['tink', 'state'], name: 'Observable' }, [t]):
                switch merge(t) {
                  case macro ($single : $data):
                    var et = expectedType.toComplex();
                    if ((macro ($single : $et)).typeof().isSuccess())
                      single;
                    else
                      macro @:pos(primary.pos) tink.state.Observable.auto(function ():$data return $single);
                  case other:
                    var ct = t.toComplex();
                    macro @:pos(primary.pos) tink.state.Observable.auto(function ():$ct return $other);
                }
              case v: 
                switch primary.expr {
                  case EObjectDecl([]) if (rest.length == 1):
                    var ct = v.toComplex();
                    macro @:pos(rest[0].pos) (${rest[0]} : $ct);//TODO: this is essentially copy pasted from above
                  default:
                    primary.pos.error('Attempting to call a function that expects ${v.toString()} instead of attributes');
                }
            }
        merge(v);
    }
  }
    
}

