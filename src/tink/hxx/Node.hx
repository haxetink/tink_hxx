package tink.hxx;

import haxe.macro.Expr;
using tink.CoreApi;

enum ChildKind {
  CLet(vars:Array<Attribute>, c:Children);
  CIf(cond:Expr, cons:Children, alt:Children);
  CFor(head:Expr, body:Children);
  CSwitch(target:Expr, cases:Array<{ values:Array<Expr>, ?guard:Expr, children:Children }>);
  CNode(node:Node);
  CText(text:StringAt);
  CExpr(e:Expr);
  CSplat(e:Expr);
}

private typedef ChildData = {>Located<ChildKind>,
  var isConstant(default, null):Lazy<Bool>;
}

@:forward
abstract Child(ChildData) from ChildData to ChildData {

  public function map(fn:Child->Child):Child {
    function rec(c:Children)
      return switch c {
        case null | { value: []}: c;
        default: { value: [for (c in c.value) fn(c)], pos: c.pos };
      }

    var val = switch this.value {
      case CLet(vars, c):
        CLet(vars, rec(c));
      case CIf(cond, cons, alt):
        CIf(cond, rec(cons), rec(alt));
      case CFor(head, body):
        CFor(head, rec(body));
      case CSwitch(target, cases):
        CSwitch(target, [for (c in cases) { values: c.values, guard: c.guard, children: rec(c.children)}]);
      case CNode(node):
        CNode({
          name: node.name,
          attributes: node.attributes,
          children: rec(node.children),
        });
      default: this.value;
    }
    return
      if (val == this.value) this
      else { pos: this.pos, value: val };
  }

  public function transform(fn:Child->Child) {
    function apply(target:Child) {
      return fn(target.map(apply));
    }
    return apply(this);
  }

  @:from static function ofLocated(l:Located<ChildKind>):Child
    return {
      pos: l.pos,
      value: l.value,
      isConstant: Lazy.ofFunc(function () return #if macro IsConstant.kind(l.value) #else false #end),
    }
}

typedef Node = {
  name:StringAt,
  attributes:Array<Attribute>,
  ?children:Children
}

typedef Children = Located<Array<Child>>;