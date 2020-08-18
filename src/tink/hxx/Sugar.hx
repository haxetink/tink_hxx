package tink.hxx;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

using tink.MacroApi;

class Sugar {

  static public function markupOnlyFunctions(f:Function) {
    var e = f.expr;

    if (e == null) return f;

    while (true) switch e.expr {
      case EBlock([v]): e = v;
      default: break;
    }

    if (e.expr.match(EConst(CString(_)))) {
      var pos = {
        var full = Context.getPosInfos(e.pos);
        Context.makePosition({
          min: full.min,
          max: full.min,
          file: full.file
        });
      }
      e = macro @:pos(pos) @hxx $e;
    }

    var e2 = applyMarkup(e);

    return
      if (e == e2) f;
      else { args: f.args, expr: macro @:pos(e2.pos) return $e2, ret: f.ret, params: f.params };
  }

  static public function applyMarkup(e:Expr)
    return switch e {
      case macro @hxx $v:
        macro @:pos(e.pos) hxx($v);
      case macro @:markup $v:
        v = {
          expr: v.expr,
          pos: {
            var p = Context.getPosInfos(v.pos);
            Context.makePosition({//this is awkward
              file: p.file,
              min: p.min - 1,
              max: p.max + 1,
            });
          }
        }
        macro @:pos(e.pos) hxx($v);
      default: e;
    }

  static public function transformExpr(e:Expr)
    return switch e {
      case { expr: EFunction(name, f) }:
        EFunction(name, markupOnlyFunctions(f)).at(e.pos);
      default: applyMarkup(e);
    }
}
#end