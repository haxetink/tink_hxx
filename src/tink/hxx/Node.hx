package tink.hxx;

import haxe.macro.Expr;
using haxe.macro.ExprTools;
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

  function childrenString(children:Children)
    return switch children {
      case null | { value: [] }: '';
      case { value: a }: [for (c in a) c.toString()].join('');
    }

  public function toString()
    return switch this.value {
      case CLet(vars, c):
        var ret = '<let ';
        for (a in vars)
          ret += ' ' + attrString(a);

        ret = '>' + childrenString(c) + '</let>';

      case CIf(cond, cons, alt):
        '<if $${${cond.toString()}}>${childrenString(cons)}' + (switch childrenString(alt) {
          case '': '';
          case v: '<else>$v';
        }) + '</if>';
      case CFor(head, body):
        '<for $${${head.toString()}}>${childrenString(body)}</for>';
      case CSwitch(target, cases):
        '';
      case CNode(node):
        var ret = '<${node.name.value}';
        for (a in node.attributes)
          ret += ' ' + attrString(a);
        ret += switch childrenString(node.children) {
          case '': '/>';
          case v: v + '</${node.name.value}>';
        };
        ret;
      case CText(text):
        text.value;
      case CExpr(e):
        exprString(e);
      case CSplat(e):
        exprString(e, true);
    }

  static function attrString(a:Attribute)
    return switch a {
      case Splat(e): exprString(e, true);
      case Empty({ value: name }): name;
      case Regular({ value: name }, value): '$name=${exprString(value)}';
    }

  static function exprString(e:Expr, ?splat)
    return '$${' + (if (splat) '...' else '') + e.toString() + '}';
}

typedef Node = {
  name:StringAt,
  attributes:Array<Attribute>,
  ?children:Children
}

typedef Children = Located<Array<Child>>;