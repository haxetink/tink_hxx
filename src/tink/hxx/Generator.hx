package tink.hxx;

#if macro
import tink.hxx.Node;
import tink.hxx.Tag;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.hxx.Helpers.*;
import tink.anon.Macro.*;
import tink.anon.Macro;

using haxe.macro.Tools;
using tink.CoreApi;
using tink.MacroApi;
using StringTools;

class Generator {
  dynamic function adjustFormattingPos(pos:Position)
    return pos;

  public var defaults(default, null):Lazy<Array<Named<Position->Tag>>>;

  public function new(?defaults) {
    this.defaults = switch defaults {
      case null: [];
      case v: v;
    }

    var shift = {
      var pos = (macro null).pos;
      Context.getPosInfos(('foo'.formatString(pos):Expr).pos).min - Context.getPosInfos(pos).min;
    }
    if (shift != 0)
      adjustFormattingPos = function (p) {
        var infos = Context.getPosInfos(p);
        return Context.makePosition({ min: infos.min - shift, max: infos.max - shift, file: infos.file });
      }
  }

  function children(c:Children, ?yield:Expr->Expr)
    return switch [c.value, yield] {
      case [[], null]: c.pos.error('empty HXX');
      case [[], _]: macro @:pos(c.pos) {};
      case [[v], null]: child(v);
      case [v, null]: v[1].pos.error('single child expected');
      case [v, _]: switch [for (c in v) child(c, yield)] {
        case [v]: v;
        case v: v.toBlock((macro null).pos);
      }
    }

  function tag(n:Node, tag:Tag, pos:Position) {

    var aliases = tag.args.aliases,
        children = tag.args.children,
        fields = tag.args.fields,
        fieldsType = tag.args.fieldsType,
        childrenAttribute = tag.args.childrenAttribute;

    var tagName = {
      value: tag.name,
      pos: n.name.pos
    };

    var spreads = [
      for (a in n.attributes) switch a {
        case Splat(e): e;
        default: continue;
      }
    ];

    var custom = [],
        specials = new Map();

    var attributes = {

      var ret:Array<Part> = [];

      function set(name:StringAt, value:Expr)
        switch name.value {
          case special if (tag.hxxMeta.exists(special)):
            specials[special] = switch specials[special] {
              case null: value;
              default: name.pos.error('duplicate $special');
            }
          case _.indexOf('-') => -1:
            ret.push(makePart(name, value));
          default:
            custom.push(new NamedWith(name, value));
        }

      for (a in groupDotPaths(n.attributes)) switch a {//not 100% if grouping dot path transformation here is the best place
        case Regular(name, value): set(name, switch value.getString() {
          case Success(s):// if (s.indexOf('$') != -1):
            s.formatString(adjustFormattingPos(value.pos));
          default: value;
        });
        case Empty(name): set(name, macro @:pos(name.pos) true);
        default: continue;
      }

      ret;
    }

    var childList = n.children;

    if (children == null && childList != null) {
      for (c in n.children.value) // probably normalize should do the trick here
        switch c.value {
          case CText(_.value.trim() => ''):
          case CNode(n):
            switch fields[n.name.value] {
              case null:
                n.name.pos.error('<${tag.name}> does not accept child <${n.name.value}>');//TODO: add suggestions
              case { type: t }:
                attributes.push(complexAttribute(n));
            }
          default:
            c.pos.error('Only named tags allowed here');
        }
      childList = null;
    }

    attributes = mangle(attributes, custom, fields, tag.args.custom);

    var children = switch childList {
      case null: None;
      case l:

        function get()
          return applyCustomRules(tag.args.children, this.childList.bind(l, _));

        switch childrenAttribute {
          case null:
            Some(get());
          case name:
            attributes.push({
              name: name,
              pos: l.pos,
              getValue: function (_) return get(),
            });
            None;
        }
    }

    var args = children.toArray();
    var compute =
      if (spreads.length > 0) later;
      else function (fn) return fn();

    args.unshift(
      compute(function () {
        var paramatrized = tag.parametrized();
        var attrType = paramatrized.fieldsType;

        return mergeParts(
          attributes,
          spreads,
          paramatrized.requiredFields,
          function (name) return switch aliases[name] {
            case null: name;
            case v: v;
          },
          n.name.pos,
          attrType,
          {
            unknownField: function (p) return switch p.name {
              case name = _.indexOf('-') => -1:
                Failure('<${n.name.value}> has no attribute $name${attrType.getFieldSuggestions(name)}');
              default:
                Success(({
                  name: p.name,
                  optional: false,
                  write: WPlain,//doesn't really matter because it is marked non-optional
                  type: None,
                }:FieldInfo));
            },
            duplicateField: function (name) return 'duplicate attribute $name',
            missingField: function (f) return 'missing attribute ${f.name}',//TODO: might be nice to put type here
          }
        );
      })
    );

    if (tag.hxxMeta.keys().hasNext())
      args.unshift(EObjectDecl([for (k in specials.keys()) { field: k, expr: specials[k] }]).at(n.name.pos));

    return invoke({ value: tag.realPath, pos: tagName.pos }, tag.create, args, tagName.pos);
  }

  function later(fn:Void->Expr)
    return withTags.bind(localTags, fn).bounce();

  function makePart(name:StringAt, value:Expr, ?quotes):Part
    return {
      name: switch name.value {
        case 'class': 'className';
        case 'for': 'htmlFor';//consider moving this out into the spec
        case v: v;
      },
      pos: name.pos,
      quotes: quotes,
      getValue: function (expected:Option<Type>) {
        value = postProcess(value);
        return
          switch expected {
            case Some(t):
              applyCustomRules(t, functionSugar.bind(value));
            default:
              value;
          }
        }
    };

  function applyCustomRules(t, getValue:Type->Expr) {
    var transform = getTransform(t);
    t = transform.reduced.or(t);
    var e = getValue(t);
    return switch transform.postprocessor {
      case PTyped(f): f.bind(e).bounce();
      case PUntyped(f): f(e);
      default: e;
    }
  }

  function invoke(name:StringAt, create:TagCreate, args:Array<Expr>, pos:Position)
    return
      switch create {
        case New:
          name.value.instantiate(args, pos);
        case FromHxx:
          var e = '${name.value}.fromHxx'.resolve(name.pos);
          #if (haxe_ver >= 4.1)
          if (Context.containsDisplayPosition(e.pos)) {
            e = {expr: EDisplay(e, DKMarked), pos: e.pos};
          }
          #end
          e.call(args, pos);
        case Call:
          var e = name.value.resolve(name.pos);
          #if (haxe_ver >= 4.1)
          if (Context.containsDisplayPosition(e.pos)) {
            e = {expr: EDisplay(e, DKMarked), pos: e.pos};
          }
          #end
          e.call(args, pos);
    }

  function isOnlyChild(t:Type)
    return !Context.unify(Context.getType('Array'), t.reduce());

  function complexAttribute(n:Node):Part {
    var localTags = localTags;
    return {
      name: n.name.value,
      pos: n.name.pos,
      getValue: function (t)
        return applyCustomRules(
          switch t {
            case None: n.name.pos.error('cannot determine node type');//should not happen, but one never knows
            case Some(t): t;
          },
          function (t:Type)
            return switch t {
              case TFun(requiredArgs, ret):
                var declaredArgs = [for (a in n.attributes) switch a {
                  case Splat(e):
                    e.reject('Invalid spread on property ${n.name.value}:$t');
                  case Empty(name):
                    name;
                  case Regular(name, _):
                    name.pos.error('Invalid attribute on complex property');
                }];

                var splat = false;
                var args:Array<FunctionArg> =
                  switch [requiredArgs.length, declaredArgs.length] {
                    case [1, 0]:
                      splat = true;
                      [{
                        name: '__data__',
                        type: requiredArgs[0].t.toComplex(),
                        opt: requiredArgs[0].opt
                      }];
                    case [l, l2] if (l == l2):
                      [for (i in 0...l) {
                        name: declaredArgs[i].value,
                        type: requiredArgs[i].t.toComplex(),
                        opt: requiredArgs[i].opt
                      }];
                    case [l1, l2]:
                      if (l2 > l1) declaredArgs[l1].pos.error('too many arguments');
                      else n.name.pos.error('not enough arguments');
                  }

                function getBody()
                  return this.childList(n.children, ret);

                var body =
                  if (splat) {
                    var tags = switch requiredArgs[0].t.getFields() {
                      case Success(fields):
                        var ret =
                          #if haxe4
                            localTags.copy();
                          #else
                            [for (t in localTags.keys()) t => localTags[t]];
                          #end

                        for (c in fields)
                          ret[c.name] = Tag.declaration.bind(c.name, _, c.type, c.params);

                        ret;
                      default:
                        localTags;
                    }

                    macro @:pos(n.name.pos) {
                      tink.Anon.splat(__data__);
                      return ${
                        if (tags != localTags) withTags(tags, getBody)
                        else later(withTags.bind(tags, getBody))
                      };
                    }
                  }
                  else getBody();
                body.func(args).asExpr();
              default:
                childList(n.children, t);
            }
        )
    }
  }

  function childList(c:Children, ?t:Type)
    return
      if (t == null) children(c);
      else {
        var ct = t.toComplex();
        if(isOnlyChild(t)) children(c).as(t.toComplex());
        else if (requireNoArray(c)) //TODO: this is all still a bit clunky
          switch c.value {
            case [v]:
              [child(v)].toArray(v.pos).as(ct);
            default:
              switch this.children(c, function (e) return e) {
                case e = macro {}: e;
                case { expr: EBlock(exprs), pos: pos }:
                  exprs.toArray(pos).as(ct);
                case e:
                  throw 'assert';
              }
            }
        else macro {
          var __r = [];
          if (false) (__r:$ct);
          ${this.children(c, function (e) return macro __r.push($e))};
          (__r:$ct);
        }
      }

  static function requireNoArray(c:Children)
    return switch c {
      case null: false;
      case { value: [c] }: requiresNoArray(c);
      default: false;
    }

  static function requiresNoArray(c:Child) {
    return switch c.value {
      default: false;
      case CNode(_) | CText(_) | CExpr(_): true;
      case CIf(_, cons, alt):
        requireNoArray(cons) && (alt == null || requireNoArray(alt));
      case CLet(_, c):
        requireNoArray(c);
      case CSwitch(_, cases):
        var ret = true;
        for (c in cases)
          if (!requireNoArray(c.children)) {
            ret = false;
            break;
          }
        ret;
    }
  }

  function mangle(attrs:Array<Part>, custom:Array<NamedWith<StringAt, Expr>>, fields:Map<String, ClassField>, customRules:Array<CustomAttr>) {
    switch custom {
      case []:
      default:
        attrs = attrs.copy();// maybe mutation would be just fine
        var used = [for (i in 0...custom.length) false];

        function extract(r:EReg) {
          var ret = [];
          for (i in 0...custom.length)
            if (!used[i]) {
              var c = custom[i];
              if (r.match(c.name.value)) {
                used[i] = true;
                ret.push(c);
              }
            }
          return ret;
        }

        for (r in customRules)
          switch extract(r.filter) {
            case []:
            case custom:
              switch r.group {
                case Some(name):
                  var pos = custom[0].name.pos;
                  attrs.push(makePart(
                    { value: name, pos: pos },
                    EObjectDecl([for (a in custom) ({ field: a.name.value, expr: a.value, quotes: Quoted }:ObjectField)]).at(pos).as(r.type)
                  ));
                case None:
                  for (c in custom)
                    attrs.push(makePart(
                      c.name,
                      c.value.as(r.type),
                      Quoted
                    ));
              }
          }

        switch used.indexOf(false) {
          case -1:
          case i:
            var n = custom[i].name;
            n.pos.error('invalid custom attribute ${n.value}');
        }
    }

    return attrs;
  }

  function emptyElse()
    return macro null;

  function child(c:Child, ?yield:Expr->Expr) {

    inline function children(v:Children)
      return this.children(switch v {
        case null: { pos: c.pos, value: [] };
        default: v;
      }, yield);

    inline function ret(e)
      return
        if (yield == null) postProcess(e);
        else yield(postProcess(e));

    return switch c.value {
      case CExpr(e): ret(e);
      case CSplat(e):
        if (yield == null)
          c.pos.error('single child expected');
        macro @:pos(e.pos) for (_0 in ${postProcess(e)}) ${yield(macro @:pos(e.pos) _0)};
      case CText(s):
        ret(macro @:pos(s.pos) $v{s.value});
      case CSwitch(target, cases):
        ESwitch(target, [for (c in cases) {
          values: c.values,
          guard: c.guard,
          expr: children(c.children)
        }], null).at(c.pos);

      case CIf(cond, cons, alt):
        macro @:pos(c.pos) if ($cond) ${children(cons)} else ${if (alt == null && yield == null) emptyElse() else children(alt)};

      case CLet(defs, block):

        var vars = [];
        var statements = [EVars(vars).at(c.pos)];

        for (d in defs) switch d {
          case Empty(a):
            a.pos.error('empty attributes not allowed on <let>');
          case Regular(a, v):
            vars.push({
              name: a.value,
              type: null,
              expr: v,
            });
          case Splat(e):
            statements.push(macro @:pos(e.pos) tink.Anon.splat($e));
        }

        statements.push(children(block));
        statements.toBlock(c.pos);

      case CFor(head, body):
        macro @:pos(c.pos) for ($head) ${children(body)};
      case CNode(n):
        ret(node(n, c.pos));
    }
  }

  function node(n, pos)
    return tag(n, getTag(n.name), pos);

  function getTag(name:StringAt):Tag
    return Tag.resolve(localTags, name).sure();

  var localTags:Map<String, Position->Tag>;

  var postProcess:Expr->Expr = function (e) return e;

  function withTags<T>(tags, f:Void->T) {
    #if tink_syntaxhub var lastFn = postProcess; #end

    var last = localTags;
    return tink.core.Error.tryFinally(
      function () {
        localTags = tags;
        #if tink_syntaxhub
        postProcess = switch tink.SyntaxHub.exprLevel.appliedTo(new ClassBuilder()) {
          case Some(f): f;
          case None: function (e) return e;
        }
        #end
        return f();
      },
      function () {
        localTags = last;
        #if tink_syntaxhub postProcess = lastFn; #end
      }
    );
  }

  public function createContext():GeneratorContext {
    var tags = Tag.getAllInScope(defaults);
    return {
      isVoid: function (name) return Tag.resolve(tags, name).match(Success({ isVoid: true })),
      generateRoot: function (root:Children) return withTags(tags, function () return children(root)),
    }
  }

  public function root(root:Children):Expr
    return createContext().generateRoot(root);

  static public function normalize(c)
    return Helpers.normalize(c);

}

typedef GeneratorContext = {
  function isVoid(name:StringAt):Bool;
  function generateRoot(root:Children):Expr;
}
#end