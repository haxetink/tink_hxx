package tink.hxx;

#if macro
import tink.hxx.Node;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr;
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
          Context.storeTypedExpr(
            switch Context.follow(f.expr.t) {
              case TFun(_, _): f.expr;
              case TDynamic(null):
                value.reject('Cannot use `Dynamic` as callback');
              case found:
                if (Context.unify(found, t)) f.expr;
                else typed;
            }
          );
        case v: throw "assert";
      }

    function liftCallback(eventType:Type) {
      if (value.expr.match(EFunction(_, _)))
        return value;

      var evt = eventType.toComplex();

      return dedupe(macro @:pos(value.pos) function (event:$evt) $value);
    };

    return switch t.reduce() {
      case TAbstract(_.get() => { pack: ['tink', 'core'], name: 'Callback' }, [evt]):
        liftCallback(evt);
      case TFun([{ t: evt }], _.getID() => 'Void'):
        liftCallback(evt);
      case TFun([], _.getID() => 'Void'):
        dedupe(macro @:pos(value.pos) function () $value);
      default: value;
    }
  }

  static public function getCustomTransformer<T:BaseType>(r:haxe.macro.Type.Ref<T>)
    return switch r.get().meta.extract(':fromHxx') {
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

        Some({ basicType: basicType, transform: transform });

      case v: v[1].pos.error('only one @:fromHxx rule allowed per type');
    }

  static public function applyCustomRules(t:Type, getValue:Type->Expr)
    return
      switch t {
        case TAbstract(getCustomTransformer(_) => Some(r), _)
           | TInst(getCustomTransformer(_) => Some(r), _)
           | TEnum(getCustomTransformer(_) => Some(r), _)
           | TType(getCustomTransformer(_) => Some(r), _):

          var ret =
            if (r.basicType != null) {
              var ct = t.toComplex();
              t = r.basicType.substitute({ _: macro (null: $ct) }).typeof().sure();
              applyCustomRules(t, getValue);
            }
            else getValue(t);

          switch r.transform {
            case null: ret;
            case e: e.substitute({ _: ret });
          }

        case TType(_, _) | TLazy(_) | TAbstract(_.get() => { pack: [], name: 'Null' }, _):

          applyCustomRules(t.reduce(true), getValue);

        default:

          getValue(t);
      }

}
#end