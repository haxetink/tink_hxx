package tink.hxx;

import haxe.macro.Expr;

typedef Located<T> = {
  var pos(default, null):Position;
  var value(default, null):T;
}