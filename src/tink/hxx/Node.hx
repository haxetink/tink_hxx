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

typedef Child = Located<ChildKind>;

typedef Node = {
  name:StringAt,
  attributes:Array<Attribute>,
  ?children:Children
}

typedef Children = Located<Array<Child>>;