package tink.hxx;

#if macro
import tink.hxx.Node;
import tink.hxx.Tag;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.anon.Macro.*;
import tink.anon.Macro;

using haxe.macro.Tools;
using tink.CoreApi;
using tink.MacroApi;
using StringTools;

class Generator {
  static inline var OUT = '__r';
  public var defaults(default, null):Lazy<Array<Named<Position->Tag>>>;

  public function new(?defaults) 
    this.defaults = switch defaults {
      case null: [];
      case v: v;
    }

  function yield(e:Expr) 
    return macro @:pos(e.pos) $i{OUT}.push($e);

  function flatten(c:Children) 
    return 
      if (c == null) null;
      else switch normalize(c.value) {
        case []: noChildren(c.pos);
        case v: [for (c in v) child(c, flatten)].toBlock(c.pos);
      }

  function noChildren(pos)
    return macro @:pos(pos) null;

  function mangle(attrs:Array<Part>, custom:Array<NamedWith<StringAt, Expr>>, childrenAttribute:Null<String>, children:Option<Expr>, fields:Map<String, ClassField>, customRules:Array<CustomAttr>) {
    switch custom {
      case []:
      default:
        
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
                  attrs = attrs.concat([
                    makeAttribute({ value: name, pos: pos }, EObjectDecl([for (a in custom) ({ field: a.name.value, expr: a.value, quotes: Quoted }:ObjectField)]).at(pos).as(r.type)) 
                  ]);
                case None:
                  attrs = attrs.concat([for (c in custom) makeAttribute(c.name, c.value.as(r.type), Quoted)]);
              }
          }

        switch used.indexOf(false) {
          case -1: 
          case i:
            var n = custom[i].name;
            n.pos.error('invalid custom attribute ${n.value}');
        }
    }

    if (childrenAttribute != null)
      switch children {
        case Some(e):
          attrs = attrs.concat([
            makeAttribute({ value: childrenAttribute, pos: e.pos }, e)
          ]);
          children = None;
        default:
      }

    return {
      attrs: attrs,
      children: children, 
    }
  }

  static function getCustomTransformer<T:BaseType>(r:haxe.macro.Type.Ref<T>)
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

  function functionSugar(value:Expr, t:Type) {
    function liftCallback(eventType:Type) 
      return later(function () {
        while (true) switch value {
          case macro ($v): value = v;
          default: break;
        }
        if (value.expr.match(EFunction(_, _)))
          return value;

        var evt = eventType.toComplex();

        return switch Context.typeExpr(macro @:pos(value.pos) function (event:$evt) $value) {
          case typed = { expr: TFunction(f) }:
            Context.storeTypedExpr(
              switch Context.follow(f.expr.t) {
                case TFun(_, _): f.expr;
                case TDynamic(null): value.reject('Cannot use `Dynamic` as callback');
                case found: 
                  if (Context.unify(found, t)) f.expr;
                  else typed;
              }
            );
          case v: throw "assert";
        }
      });
    return switch t.reduce() {
      case TAbstract(_.get() => { pack: ['tink', 'core'], name: 'Callback' }, [evt]):
        liftCallback(evt);
      case TFun([{ t: evt }], _.getID() => 'Void'):
        liftCallback(evt);
      case TFun([], _.getID() => 'Void'):
        later(function () {
          var typed = Context.typeExpr(value);
          var body = Context.storeTypedExpr(typed);
          return 
            if (typed.t.reduce().match(TFun(_, _))) body;
            else macro @:pos(value.pos) function () $body;
        });
      default: value;
    }    
  }

  function applyCustomRules(t:Type, getValue:Type->Expr) 
    return
      switch t {
        case TAbstract(getCustomTransformer(_) => Some(r), _),
             TInst(getCustomTransformer(_) => Some(r), _),
             TEnum(getCustomTransformer(_) => Some(r), _),
             TType(getCustomTransformer(_) => Some(r), _):
          
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

  function makeAttribute(name:StringAt, value:Expr, ?quotes):Part
    return {
      name: switch name.value {
        case 'class': 'className';
        case 'for': 'htmlFor';//consider moving this out into the spec
        case v: v;
      },
      pos: name.pos,
      quotes: quotes,
      getValue: function (expected:Option<Type>) 
        return 
          switch expected {
            case Some(t):
              applyCustomRules(t, functionSugar.bind(value));
            default: 
              value;
          }
    };

  function instantiate(name:StringAt, create:TagCreate, key:Option<Expr>, attr:Expr, children:Option<Expr>)
    return switch key {
      case None:
        invoke(name, create, [attr].concat(children.toArray()), name.pos);
      case Some(key):
        key.reject('key handling not available in this HXX flavor');        
    }

  function invoke(name:StringAt, create:TagCreate, args:Array<Expr>, pos:Position)
    return 
      switch create {
        case New:
          name.value.instantiate(args, pos);
        case FromHxx:
          '${name.value}.fromHxx'.resolve(pos).call(args, pos);
        case Call:
          name.value.resolve(pos).call(args, pos);  
      }

  function node(n:Node, pos:Position) 
    return tag(n, getTag(n.name), pos);

  function plain(name:StringAt, create:TagCreate, arg:Expr, pos:Position)
    return invoke(name, create, [arg], pos);

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
    
    var splats = [
      for (a in n.attributes) switch a {
        case Splat(e): e;
        default: continue;
      }
    ];
    
    var key = None,
        custom = [];
    
    var attributes = {
      
      var ret:Array<Part> = [];

      function set(name, value) {
        if (name.value == 'key' && !fields.exists('key')) 
          key = Some(value);
        else if (name.value.indexOf('-') == -1) 
          ret.push(makeAttribute(name, value));
        else 
          custom.push(new NamedWith(name, value));
      }
      
      for (a in groupDotPaths(n.attributes)) switch a {//not 100% if grouping dot path transformation here is the best place
        case Regular(name, value): set(name, switch value.getString() {
          case Success(s): s.formatString(value.pos);
          default: value;
        });
        case Empty(name): set(name, macro @:pos(name.pos) true);
        default: continue;
      }

      ret;
    }
    var childList = n.children;
    
    if (children == null && childList != null) {
      for (c in n.children.value)
        switch c.value {
          case CText(_.value.trim() => ''):
          case CNode(n):
            attributes.push({
              pos: n.name.pos,
              name: n.name.value,
              getValue: complexAttribute(n),
            });
          default: 
            c.pos.error('Only named tags allowed here');
        }
      childList = null;
    }

    var mangled = mangle(attributes, custom, childrenAttribute, switch childList {
      case null: None;
      case v: 
        Some(makeChildren(v, children, true));
    }, fields, tag.args.custom);

    var attrType = fieldsType.toComplex();

    var obj = 
      mergeParts(
        mangled.attrs, 
        splats,
        function (name) return switch fields[name] {
          case null: 
            if (name.indexOf('-') == -1)
              Failure(new Error('<${n.name.value}> has no attribute $name${attrType.getFieldSuggestions(name)}'));
            else
              Success(None);
          case f: Success(Some((f:FieldInfo)));
        },
        function (name) return switch aliases[name] {
          case null: name;
          case v: v;
        },
        n.name.pos,
        attrType
      );

    return instantiate(tagName, tag.create, key, obj, mangled.children);
  }

  function complexAttribute(n:Node) 
    return function (t:Option<Type>):Expr       
      return applyCustomRules(
        switch t {
          case Some(t): t;
          case None: Context.typeof(macro @:pos(n.name.pos) null);
        },
        function (t) return switch t {
          case TFun(requiredArgs, ret):
            var declaredArgs = [for (a in n.attributes) switch a {
              case Splat(e): 
                e.reject(
                  if (e.getIdent().isSuccess())
                    'Use empty attribute instead of spread operator on ident to define argument name'
                  else
                    'Invalid spread on property ${n.name.value}:$t'
                );
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

            var body =      
              later(makeBody.bind(n.children, ret));
            if (splat)
              body = macro @:pos(body.pos) {
                tink.Anon.splat(__data__);
                return $body;
              }
            body.func(args).asExpr();
          default: 
            makeChildren(n.children, t, true);
        }
      );

  function getTag(name:StringAt):Tag 
    return Tag.resolve(localTags, name).sure();

  function isOnlyChild(t:Type) 
    return !Context.unify(Context.typeof(macro []), t);

  function makeChildren(c:Children, t:Type, root:Bool) 
    return applyCustomRules(t, function (t) {
      var ct = t.toComplex();
      return
        if (isOnlyChild(t))
          onlyChild(c, root, ct);
        else
          macro @:pos(c.pos) {
            var $OUT = [];
            ($i{OUT} : $ct);
            ${flatten(c)};
            $i{OUT};
          }
    });

  function makeBody(c:Children, t:Type)
    return makeChildren(c, t, true);

  function child(c:Child, flatten:Children->Expr):Expr
    return switch c.value {
      case CExpr(e): yield(e);
      case CSplat(e): 
        child({ 
          value: CFor(
            macro @:pos(e.pos) _0 in $e, 
            {
              value: [{
                value: CExpr(macro @:pos(e.pos) _0),
                pos: e.pos,
              }],
              pos: e.pos,
            }
          ), 
          pos: e.pos 
        }, flatten);
      case CText(s): yield(s.value.toExpr(s.pos));
      case CNode(n): yield(node(n, c.pos));
      case CSwitch(target, cases): 
        ESwitch(target, [for (c in cases) {
          values: c.values,
          guard: c.guard,
          expr: 
            if (c.children != null) later(flatten.bind(c.children))//TODO: avoid bouncing here
            else null,
        }], null).at(c.pos);

      case CIf(cond, cons, alt): 
        
        macro @:pos(c.pos) if ($cond) ${flatten(cons)} else ${if (alt == null) emptyElse() else flatten(alt)};

      case CLet(defs, c):

        var vars:Array<Var> = [];
        function add(name, value)
          vars.push({
            name: name,
            type: null,
            expr: value,
          });

        for (d in defs) switch d {
          case Empty(a): a.pos.error('empty attributes not allowed on <let>');
          case Regular(a, v):
            add(a.value, v);
          case Splat(e):
            var tmp = MacroApi.tempName();
            add(tmp, e);
            for (f in e.typeof().sure().getFields().sure()) 
              if (f.isPublic && !f.kind.match(FMethod(MethMacro)))
                add(f.name, macro @:pos(e.pos) $p{[tmp, f.name]});
        }
        
        [EVars(vars).at(c.pos), later(flatten.bind(c))].toBlock(c.pos);//TODO: find a reliable solution without bouncing

      case CFor(head, body): 
        
        macro @:pos(c.pos) for ($head) ${
          flatten.bind(body).inSubScope(switch head {
            case macro $i{name} in $target: 
              var type = (macro @:pos(head.pos) (function () {
                for ($head) return $i{name};
                return cast null;
              })()).typeof().sure().toComplex();
              [{
                name: name,
                type: type,
                expr: macro cast null,
              }];
            default: head.reject('invalid loop head');
          })
        };
    }

  function emptyElse()
    return macro null;

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

  function onlyChild(c:Children, ?root = true, ?expected:ComplexType) 
    return switch normalize(c.value) {
      case []: c.pos.error('Empty HXX');
      case [v]: 
        var child = child(v, this.onlyChild.bind(_, false));
        if (root) {
          if (expected == null)
            macro @:pos(c.pos) {
              var $OUT = [];
              $child;
              $i{OUT}[0];
            }
          else
            macro @:pos(c.pos) {
              var $OUT:Array<$expected> = [];
              $child;
              $i{OUT}[0];
            }            
        }
        else child;
      case v: v[1].pos.error('Only one element allowed here');
    }  

  var localTags:Map<String, Position->Tag>;
  
  function withTags<T>(tags, f:Void->T) {
    var last = localTags;
    return tink.core.Error.tryFinally(
      function () {
        localTags = tags;
        return f();
      },
      function () localTags = last
    );
  }

  function later(e:Void->Expr) 
    return withTags.bind(localTags, e).bounce();

  public function createContext():GeneratorContext {
    var tags = Tag.getAllInScope(defaults);
    return {
      isVoid: function (name) return Tag.resolve(tags, name).match(Success({ isVoid: true })),
      generateRoot: function (root:Children) return withTags(tags, function () return onlyChild.bind(root).scoped()),
    }
  }

  public function root(root:Children):Expr 
    return createContext().generateRoot(root);

}

typedef GeneratorContext = {
  function isVoid(name:StringAt):Bool;
  function generateRoot(root:Children):Expr;
}
#end