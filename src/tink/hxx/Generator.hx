package tink.hxx;

#if macro
import tink.hxx.Node;
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
  public var defaults(default, null):Lazy<Array<Named<Tag>>>;

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
        // case [v]:
        case v: [for (c in v) child(c, flatten)].toBlock(c.pos);
      }

  function noChildren(pos)
    return macro @:pos(pos) null;

  function mangle(attrs:Array<Part>, custom:Array<NamedWith<StringAt, Expr>>, childrenAreAttribute:Bool, children:Option<Expr>, fields:Map<String, ClassField>) {
    switch custom {
      case []:
      default:
        var pos = custom[0].name.pos;
        attrs = attrs.concat([
          makeAttribute({ value: 'attributes', pos: pos }, EObjectDecl([for (a in custom) { field: a.name.value, expr: a.value }]).at(pos)) 
        ]);
    }

    if (childrenAreAttribute)
      switch children {
        case Some(e):
          attrs = attrs.concat([
            makeAttribute({ value: 'children', pos: e.pos }, e)
          ]);
          children = None;
        default:
      }
    return {
      attrs: attrs,
      children: children, 
    }
  }

  function makeAttribute(name:StringAt, value:Expr):Part
    return {
      name: switch name.value {
        case 'class': 'className';
        case 'for': 'htmlFor';
        case v: v;
      },
      pos: name.pos,
      getValue: function (expected:Option<Type>) 
        return 
          switch expected {
            case Some(_.reduce() => t):
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
                        switch Context.followWithAbstracts(f.expr.t) {
                          case TFun(_, _): f.expr;
                          default: 
                          typed;
                        }
                      );
                    case v: throw "assert";
                  }
                });
              switch t {
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
            default: 
              value;
          }
    };

  function instantiate(name:StringAt, isClass:Bool, key:Option<Expr>, attr:Expr, children:Option<Expr>)
    return switch key {
      case None:
        invoke(name, isClass, [attr].concat(children.toArray()), name.pos);
      case Some(key):
        key.reject('key handling not available in this HXX flavor');        
    }

  function invoke(name:StringAt, isClass:Bool, args:Array<Expr>, pos:Position)
    return 
      if (isClass)
        name.value.instantiate(args, pos);
      else
        name.value.resolve(pos).call(args, pos);  

  function node(n:Node, pos:Position) 
    return tag(n, getTag(n.name), pos);

  function plain(name:StringAt, isClass:Bool, arg:Expr, pos:Position)
    return invoke(name, isClass, [arg], pos);

  function tag(n:Node, tag:Tag, pos:Position) {
    var children = null,
        fields = null,
        fieldsType = null,
        childrenAreAttribute = false;
    var tagName = {
      value: tag.name,
      pos: n.name.pos
    };
    switch tag.args {
      case PlainArg(t):
        if (n.children != null) 
          tagName.pos.error('children not allowed on <${tagName.value}/>');
        switch n.attributes {
          case [Splat(e)]:
            return plain(tagName, tag.isClass, e, pos);
          default: 
            tagName.pos.error('<${tagName.value}/> must have exactly one spread and no other attributes');
        }
        
      case JustAttributes(a, t):

        fieldsType = t;
        fields = a;

      case Full(a, t, c, caa):

        fields = a;
        fieldsType = t;
        children = c;      
        childrenAreAttribute = caa;
    }
    
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
      
      for (a in n.attributes) switch a {
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

    var mangled = mangle(attributes, custom, childrenAreAttribute, switch childList {
      case null: None;
      case v: 
        Some(makeChildren(v, children.toComplex(), true));
    }, fields);

    var attrType = fieldsType.toComplex();

    var obj = 
      mergeParts(
        mangled.attrs, 
        splats,
        function (name) return switch fields[name] {
          case null: Failure(new Error('Superflous field `$name`'));
          case f: Success(Some((f:FieldInfo)));
        },
        attrType
      );

    return instantiate(tagName, tag.isClass, key, obj, mangled.children);
  }

  function complexAttribute(n:Node) {
    return function (t:Option<Type>):Expr return switch t {
      case Some(TFun(requiredArgs, ret)):
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
          later(makeBody.bind(n.children, ret.toComplex()));
        if (splat)
          body = macro @:pos(body.pos) {
            tink.Anon.splat(__data__);
            return $body;
          }
        body.func(args).asExpr();
      default: 
        makeChildren(n.children, switch t {
          case Some(t): t.toComplex();
          default: n.name.pos.makeBlankType();
        }, true);
    };    
  }

  function getTag(name:StringAt):Tag 
    return (switch localTags[name.value] {
      case null: 
        localTags[name.value] = tagDeclaration.bind(name.value, _, name.value.resolve(name.pos).typeof().sure());
      case get: get;
    })(name.pos);

  function isOnlyChild(ct:ComplexType)
    return !(macro for (i in (null:$ct)) {}).typeof().isSuccess();

  function makeChildren(c:Children, ct:ComplexType, root:Bool)
    return
      if (isOnlyChild(ct))
        onlyChild(c, root, ct);
      else
        macro @:pos(c.pos) {
          var $OUT = [];
          ($i{OUT} : $ct);
          ${flatten(c)};
          $i{OUT};
        }

  function makeBody(c:Children, ct:ComplexType)
    return makeChildren(c, ct, true);

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
          expr: later(flatten.bind(c.children)),//TODO: avoid bouncing here
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
        
        [EVars(vars).at(c.pos), flatten.bind(c).inSubScope(vars)].toBlock(c.pos);

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

  static function makeArgs(pos:Position, t:Type, ?children:Type):TagArgs {
    function anon(anon:AnonType, t, lift:Bool, children:Type) {
      var fields = [for (f in anon.fields) f.name => f];
      
      var childrenAreAttribute = fields.exists('children');
      
      if (childrenAreAttribute) {
        if (children == null) 
          children = fields['children'].type;
        else 
          pos.error('tag requires child list and children attribute');
      }
      return 
        if (children == null)
          JustAttributes(fields, t);
        else
          Full(fields, t, children, childrenAreAttribute);
    }    

    return 
      switch t.reduce() {
        case TAnonymous(a):
          anon(a.get(), t, false, children);
        default:
          if (children != null) throw 'assert';
          PlainArg(t);
      }
  }

  var localTags:Map<String, Position->Tag>;
  
  static public function extractTags(e:Expr) {
    return function () {
      var name = {
        
        var cur = e,
            ret = [];
        
        while (true) switch cur {
          case macro @:pos(p) $v.$name:
            cur = v;
            ret.push(name);
          case macro $i{name}:
            ret.push(name);
            break;
          default: cur.reject('dot path expected');
        }

        ret.reverse();
        ret.join('.');
      }

      return [for (f in e.typeof().sure().getFields().sure())
        if (f.isPublic) switch f.kind {
          case FMethod(MethMacro): continue; 
          case FMethod(_): 
            new Named(
              f.name, 
              tagDeclaration('$name.${f.name}', f.pos, f.type)
            );
          default: continue;
        }
      ];
    }
  }

  static public function tagDeclaration(name:String, pos:Position, type:Type):Tag {

    function mk(a, ?c, ?isClass):Tag
      return {
        isClass: isClass, 
        args: makeArgs(pos, a, c), 
        name: name,
      };

    return
      switch type.reduce() {
        case TFun([{ t: a }, { t: c }], _): 
          mk(a, c);
        case TFun([{ t: a }], _): 
          mk(a);  
        case v:
          return switch '${name}.new'.resolve(pos).typeof() {
            case Success(TFun([{ t: a }, { t: c }], _)):
              mk(a, c, true);
            case Success(TFun([{ t: a }], _)):
              mk(a, true);
            default:
              pos.error(
                if (Context.defined('display') && v.match(TMono(_.get() => null))) 'unknown tag $name'
                else '$name has type $v which is unsuitable for HXX'
              );
          }          
      }
  }

  function getLocalTags() {
    var localTags = new Map();
    function add(name, type)
      localTags[name] = {
        var ret = null;
        function (pos) {
          if (ret == null) 
            ret = tagDeclaration(name, pos, type);
          return ret;
        }
      }
    var vars = Context.getLocalVars();
    for (name in vars.keys())
      add(name, vars[name]);

    switch Context.getLocalType() {
      case null:
      case v = TInst(_.get().statics.get() => statics, _):

        var fields = [for (f in v.getFields(false).sure()) f.name => f],
            method = Context.getLocalMethod();

        if (fields.exists(method) || method == 'new') 
          for (f in fields) 
            if (f.kind.match(FMethod(MethNormal | MethInline | MethDynamic))) {
              var name = f.name;
              add(name, (macro @:pos(f.pos) this.$name).typeof().sure());
            }
        for (f in statics)
          add(f.name, f.type);

      default:
    }
    for (d in defaults.get())
      localTags[d.name] = function (_) return d.value;
    return localTags;
  } 

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

  public function root(root:Children):Expr 
    return withTags(getLocalTags(), function () return onlyChild.bind(root).scoped());

}

enum TagArgs {
  PlainArg(t:Type);
  JustAttributes(fields:Map<String, ClassField>, fieldsType:Type);
  Full(fields:Map<String, ClassField>, fieldsType:Type, children:Type, childrenAreAttribute:Bool);
}

typedef Tag = {
  var isClass(default, never):Bool;
  var args(default, never):TagArgs;
  var name(default, never):String;
}
#end
