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

@:forward
abstract Child(Located<ChildKind>) from Located<ChildKind> to Located<ChildKind> {
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
}

typedef Node = {
  name:StringAt,
  attributes:Array<Attribute>,
  ?children:Children
}

typedef Children = Located<Array<Child>>;