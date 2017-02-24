package tink.hxx;

#if macro
import haxe.Constraints.IMap;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Context;
using haxe.macro.Tools;
using tink.MacroApi;
using tink.CoreApi;

typedef Lookup = {
  function get(key:String):{ optional:Bool, type:Type };
  function remove(key:String):Bool;
  function keys():Iterator<String>;
}
#end

class Merge {
  macro static public function lookup(name:String) {
    var pos = Context.currentPos();
    return 
      if (Context.getLocalTVars().exists(name)) macro @:pos(pos) $i{name};
      else 
        try
          Context.storeTypedExpr(Context.typeExpr(macro @:pos(pos) __data__.$name))
        catch (e:Dynamic)
          macro @:pos(pos) $i{name};
  }
  macro static public function complexAttribute(e:Expr) {
    return
      switch Context.getExpectedType().reduce() {
        case null:
          throw 'assert';
        case TFun([{ t: t }], _):
          
          var ct = t.toComplex();
          var fields = new Map();
          
          switch [t.getID(), t.getFields()] {
            case ['Array' | 'String', _]: //TODO: handle maps as well
            case [_, Success(f)]:
              for (f in f) if (f.isPublic) fields[f.name] = true;
            default:
              macro { };
          }
          
          function substituteDollars(e:Expr)
            return switch e {
              case macro $i{"$"}: macro @:pos(e.pos) __data__;
              case macro $i{known} if (fields[known]): macro @:pos(e.pos) tink.hxx.Merge.lookup($v{known});
              case macro tink.hxx.Merge.complexAttribute(_): e;
              default: e.map(substituteDollars);
            }
            
          return macro function (__data__:$ct) {
            return ${substituteDollars(e)};
          }
          
        case v:
          e;
      }
  }
  #if macro
  static public function mergeObjects(primary:Expr, rest:Array<Expr>, options:MergeOptions) {

    function typed(expr:Expr, fallback:Expr->Expr) 
      return
        try {
          Context.storeTypedExpr(Context.typeExpr(expr));
        }
        catch (e:Dynamic) {
          if (fallback == null) expr;
          else fallback(expr);
        }
    
    function combine(type:Type, expected:Lookup) {
      var result:Array<{ field:String, expr:Expr }> = [],
          vars:Array<Var> = [];
      
      function addField(owner, name:String, expr:Expr) {
        var fType = expected.get(name).type;

        function getDefault() {
          var ct = fType.toComplex();
          return typed(macro @:pos(expr.pos) ($expr : $ct), function (e) {

            var isFunction = 
              switch expr.typeof() {
                case Success(_.reduce() => TFun(_, _) | TAbstract(_.get() => { pack: ['tink', 'core'], name: 'Callback' }, _)): true;
                default: false;
              }

            return
              switch fType.reduce() {
                case TFun([_], _) | TAbstract(_.get() => { pack: ['tink', 'core'], name: 'Callback' }, _) if (!isFunction):
                  macro @:pos(expr.pos) function (event) $expr;
                case TFun([], _) if (!isFunction):
                  macro @:pos(expr.pos) function () $expr;
                case v:
                  if (options.fixField == null) e;
                  else options.fixField(e);
              }
          });
        }
        
        result.push({ 
          field: name, 
          expr: options.genField({
            name: name,
            owner: owner,
            expected: fType, 
            getDefault: getDefault,
          }),
        });
        
        expected.remove(name);
      }

      function decompose(rest:Array<Expr>) {
        for (o in rest) {
          var vName = '__' + vars.length;
          
          vars.push({
            type: null, name: vName, expr: o,
          });
          
          var oType = o.typeof().sure();
          var owner = Some(oType);

          for (f in oType.getFields().sure()) 
            switch expected.get(f.name) {
              case null:
              default:
                var name = f.name;
                addField(owner, name, macro $i{vName}.$name);
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

      switch primary.expr {
        case EObjectDecl([]) if (rest.length == 1):
          var ct = type.toComplex();
          return typed(
            macro @:pos(rest[0].pos) (${rest[0]} : $ct),
            function (_) return options.decomposeSingle(rest[0], type, decompose)
          );
        case EObjectDecl(given):
          for (f in given)
            switch expected.get(f.field) {
              case null:
                f.expr.reject('invalid field ${f.field}');
              default:
                addField(None, f.field, f.expr);
            }
        default: 
          throw 'assert';
      }
      
      return decompose(rest);
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
              case v: 
                switch primary.expr {
                  case EObjectDecl([]) if (rest.length == 1):
                    var ct = v.toComplex();
                    typed(macro @:pos(rest[0].pos) (${rest[0]} : $ct), null);
                  default:
                    primary.pos.error('Attempting to call a function that expects ${v.toString()} instead of attributes');
                }
            }
        merge(v);
    }
  }
  #end
  macro static public function objects(primary:Expr, rest:Array<Expr>)
    return mergeObjects(primary, rest, {
      fixField: function (e) return e,
      genField: function (ctx) return ctx.getDefault(),
      decomposeSingle: function (e, _, d) return d([e]),
    });
    
}

#if macro
typedef FieldMergeContext = { 
  var name(default, null):String;
  var owner(default, null):Option<Type>;
  var expected(default, null):Type;
  function getDefault():Expr;
}

typedef MergeOptions = {
  function decomposeSingle(expr:Expr, expected:Type, decomposer:Array<Expr>->Expr):Expr;
  function genField(ctx:FieldMergeContext):Expr;
  function fixField(expr:Expr):Expr;
}
#end