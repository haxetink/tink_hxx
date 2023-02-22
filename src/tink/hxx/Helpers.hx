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

  static var measured = false;
  static public function functionSugar(value:Expr, t:Type) {

    var mode = Off;

    for (c in Context.getLocalUsing()) // TODO: doing this here might be rather expensive
      switch c.toString() {
        case 'tink.hxx.FunctionSugar':
          mode = On;
          break;
        case 'tink.hxx.DeprecatedFunctionSugar':
          mode = Deprecated;
          break;
        default:
      }

    if (mode == Off)
      return value;

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
              if (mode == Deprecated)
                e.pos.warning('Automatic function wrapping is deprecated');

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

  static var transformers = new Map<String, Option<Expr->Expr>>();

  static function getCustomTransformer<T:BaseType>(r:haxe.macro.Type.Ref<T>) {
    var id = r.toString();
    return switch transformers[id] {
      case null:
        transformers[id] = switch r.get().meta.extract(':fromHxx') {
          case []: None;
          case [{ params: params }]:

            var transform = null;

            for (p in params)
              switch p {
                case macro transform = $e: transform = e;
                case macro $e = $_: e.reject('unknown option ${e.toString()}');
                default: p.reject('should be `<name> = <option>`');
              }

            switch transform {
              case null: None;
              case v: Some(e -> v.substitute({ '_' : e }));
            }

          case v: v[1].pos.error('only one @:fromHxx rule allowed per type');
        }
      case v: v;
    }
  }

  static public function getTransform(t:Type):Expr->Expr
    return
      switch t {
        case TAbstract(getCustomTransformer(_) => Some(f), _)
           | TInst(getCustomTransformer(_) => Some(f), _)
           | TEnum(getCustomTransformer(_) => Some(f), _)
           | TType(getCustomTransformer(_) => Some(f), _):

          f;
        case TType(_, _) | TLazy(_) | TAbstract(_.get() => { pack: [], name: 'Null' }, _):
          getTransform(t.reduce(true));
        default:
          noop;
      }

  static function noop(e:Expr) return e;
}

@:enum private abstract FunctionSugarMode(Int) {
  var Off = 0;
  var On = 1;
  var Deprecated = 2;
}
#end