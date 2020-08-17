package tink.hxx;

#if macro
import tink.hxx.Node;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr;
using haxe.macro.Tools;
using StringTools;
using tink.MacroApi;
using tink.CoreApi;

class Helpers {
  static public function groupDotPaths(attributes:Array<Attribute>) {
    var hasDot = false;

    for (a in attributes)
      switch a {
        case Empty(s) | Regular(s, _):
          if (s.value.indexOf('.') != -1) {
            hasDot = true;
            break;
          }
        default:
      }

    return
      if (!hasDot) attributes;
      else {

        var ret = [],
            objects = new Map<String, Array<ObjectField>>();

        function add(path:StringAt, value:Expr) {

          var parts = path.value.split('.');
          var root = parts[0];

          if (!objects.exists(root)) {
            var fields = [];
            objects[root] = fields;
            ret.push(Attribute.Regular({ pos: path.pos, value: root }, EObjectDecl(fields).at(path.pos)));
          }

          var last = parts.pop(),
              prefix = '';

          for (p in parts) {

            var parent = prefix;

            prefix = switch prefix {
              case '': p;
              case v: '$v.$p';
            }

            if (!objects.exists(prefix)) {
              objects[prefix] = [];

              if (parent != '')
                objects[parent].push({ field: p, expr: EObjectDecl(objects[prefix]).at(path.pos) });
            }
          }

          objects[prefix].push({ field: last, expr: value });
        }

        for (a in attributes)
          switch a {
            case Empty(s) if (s.value.indexOf('.') != -1):
              add(s, macro true);
            case Regular(s, e) if (s.value.indexOf('.') != -1):
              add(s, e);
            default:
              ret.push(a);
          }
        ret;
      }
  }

  static public function normalize(children:Array<Child>)
    return switch children {
      case null: [];
      default:
        [for (c in children) switch c.value {
          case CText(s):
            switch trimString(s.value) {
              case '': continue;
              case v: { value: CText({ pos: s.pos, value: v }), pos: c.pos };
            }
          default: c;
        }];
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

  static public function functionSugar(value:Expr, t:Type) {

    while (true) switch value {
      case macro ($v): value = v;
      default: break;
    }

    switch value.expr {
      case EFunction(_): return value;
      default:
    }

    function dedupe(e:Expr)
      return switch Context.typeExpr(e) {
        case typed = { expr: TFunction(f) }:

          switch Context.follow(f.expr.t) {
            case TFun(_, _): Context.storeTypedExpr(f.expr);
            case TDynamic(null):
              value.reject('Cannot use `Dynamic` as callback');
            case found:
              if (Context.unify(found, t)) Context.storeTypedExpr(f.expr);
              else if (typed.hasThis()) macro @:pos(e.pos) (function () return $e)();
              else Context.storeTypedExpr(typed);
          }

        case v: throw "assert";
      }

    function liftCallback(eventType:Type)
      return (function () {
        var hasEvent = value.has(function (e) return switch e {
          case macro event: true;
          default: false;
        });

        if (!hasEvent)
          value = Context.storeTypedExpr(Context.typeExpr(value));

        var evt = eventType.toComplex();

        return dedupe(macro @:pos(value.pos) function (event:$evt):Void $value);
      }).bounce();

    return switch t.reduce() {
      case TAbstract(_.get() => { pack: ['tink', 'core'], name: 'Callback' }, [evt]):
        liftCallback(evt);
      case TFun([{ t: evt }], _.getID() => 'Void'):
        liftCallback(evt);
      case TFun([], _.getID() => 'Void'):

        (function () {
          var t = Context.typeExpr(value);

          return switch t.t.reduce() {
            case TFun(_): Context.storeTypedExpr(t);
            default: macro @:pos(value.pos) function () $value;
          }
        }).bounce();

      case v: value;
    }
  }

  static var transformers = new Map<String, Option<Transformer>>();

  static function getCustomTransformer<T:BaseType>(r:haxe.macro.Type.Ref<T>):Option<Transformer> {
    var id = r.toString();
    return switch transformers[id] {
      case null:
        transformers[id] = switch r.get().meta.extract(':fromHxx') {
          case []: None;
          case [{ params: params }]:

            var basicType = null,
                transform = null;

            for (p in params)
              switch p {
                case macro basicType = $e: basicType = e;
                case macro transform = $e: transform = e;
                case macro $e = $_: e.reject('unknown option ${e.toString()}');
                default: p.reject('should be `<name> = <option>`');
              }

            Some({
              reduceType: switch basicType {
                case null: function (t) return t;
                case v: function (t:Type) {
                  var ct = t.toComplex();
                  return basicType.substitute({ _: macro (null: $ct) }).typeof().sure();
                }
              },
              postprocessor:
                switch transform {
                  case null: PNone;
                  case pattern: PUntyped(function (e) return pattern.substitute({ _: e }));
                }
            });

          case v: v[1].pos.error('only one @:fromHxx rule allowed per type');
        }
      case v: v;
    }
  }

  static public function setCustomTransformer(typeID:String, transformer:Transformer)
    transformers[typeID] = Some(transformer);

  static public function getTransform(t:Type):Transform
    return
      switch t {
        case TAbstract(getCustomTransformer(_) => Some(r), _)
           | TInst(getCustomTransformer(_) => Some(r), _)
           | TEnum(getCustomTransformer(_) => Some(r), _)
           | TType(getCustomTransformer(_) => Some(r), _):

          var postprocessor:Postprocessor<Expr->Expr> = switch r.postprocessor {
            case PTyped(fn): PTyped(fn.bind(t));
            case PNone: PNone;
            case PUntyped(fn): PUntyped(fn);
          }

          switch r.reduceType(t) {
            case _ == t => true:
              {
                reduced: None,
                postprocessor: postprocessor,
              }
            case reducedType:
              var inner = getTransform(reducedType);
              {
                reduced: switch inner.reduced {
                  case None: Some(reducedType);
                  case v: v;
                },
                postprocessor: switch [inner.postprocessor, postprocessor] {
                  case [PNone, v] | [v, PNone]: v;
                  case [PUntyped(i), PUntyped(o)]:
                    PUntyped(function (e) return o(i(e)));
                  case [PUntyped(i) | PTyped(i), PUntyped(o) | PTyped(o)]:
                    PTyped(function (e) return o(i(e)));
                }
              }
          }
        case TType(_, _) | TLazy(_) | TAbstract(_.get() => { pack: [], name: 'Null' }, _):
          getTransform(t.reduce(true));
        default:
          NOOP;
      }

  static var NOOP:Transform = {
    reduced: None,
    postprocessor: PNone,
  }

}

typedef Transformer = {
  function reduceType(t:Type):Type;
  var postprocessor(default, null):Postprocessor<Type->Expr->Expr>;
}

typedef Transform = {
  var reduced(default, never):Option<Type>;
  var postprocessor(default, never):Postprocessor<Expr->Expr>;
}

enum Postprocessor<T> {
  PNone;
  PUntyped(f:Expr->Expr);
  PTyped(f:T);
}
#end