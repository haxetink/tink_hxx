package tink.hxx;

import haxe.macro.Expr;

enum Attribute {
  Splat(e:Expr);
  Empty(name:StringAt);
  Regular(name:StringAt, value:Expr);
}