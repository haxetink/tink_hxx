package tink.hxx;

#if macro
import tink.hxx.Node;
import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.Tools;
using tink.MacroApi;

class IsConstant {
  static function isPure(c:ClassType)
    return c.meta.has(':pure');

  static function isFinal(f:ClassField)
    return
      #if haxe4 f.isFinal || #end f.kind.match(FVar(AccNormal | AccInline, AccNever));

  static function texpr(e:TypedExpr, ?field) {
    if (field == null)
      field = isFinal;
    var isConst = true;

    function crawl(e:TypedExpr)
      if (e != null && isConst)
        switch e.expr {
          case TField(e, FInstance(_, _, c) | FStatic(_, c) | FAnon(c)) if (field(c.get())):
            crawl(e);
          case TNew(c, _, el) if (isPure(c.get())):
            for (e in el)
              crawl(e);
          //TODO: pure calls
          case TConst(TThis)
              | TLocal(_)
              | TCall(_)
              | TField(_)
              | TBinop(OpAssign | OpAssignOp(_), _)
              : isConst = false;
          default: e.iter(crawl);
        }

    crawl(e);

    return isConst;
  }

  static public function expr(e:Expr) {
    var isConst = true;

    function typed(e:Expr) {
      isConst = false;
      try isConst = texpr(Context.typeExpr(e))
      catch (e:Dynamic) {}
    }
    function crawl(e:Expr)
      if (e != null && isConst) switch e.expr {
        case EConst(CIdent('true' | 'false' | 'null')):
        case ECall(_) | EField(_) | EConst(CIdent(_)):
          typed(e);
        case ENew(_):
          isConst = false;
        default: e.iter(crawl);
      }
    crawl(e);
    return isConst;
  }


  static public function children(?c:Children)
    if (c == null) return true;
    else {
      for (c in c.value)
        if (!kind(c.value)) return false;
      return true;
    }

  static function attributes(a:Iterable<Attribute>) {
    for (a in a)
      switch a {
        case Splat(e) | Regular(_, e) if (!expr(e)): return false;
        default:
      }
    return true;
  }

  static function name(name:StringAt)
    try {
      return texpr(
        Context.typeExpr(name.value.resolve(name.pos)),
        function (f) return isFinal(f) || f.kind.match(FMethod(_))
      );
    }
    catch (e:Dynamic) {
      return false;
    }

  static public function kind(n:ChildKind)
    return switch n {
      case CLet(vars, c): false;
      case CIf(cond, cons, alt):
        expr(cond) && children(cons) && children(alt);
      case CFor(head, body):
        expr(head) && children(body);
      case CSwitch(target, cases):
        false;
      case CNode(n):
        name(n.name) && children(n.children) && attributes(n.attributes);
      case CText(text):
        true;
      case CExpr(e) | CSplat(e):
        expr(e);
    }
}
#end