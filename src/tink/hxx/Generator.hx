package tink.hxx;

#if macro
import tink.hxx.Node;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import tink.anon.Macro.*;
import tink.anon.Macro.Part;

using haxe.macro.Tools;
using tink.CoreApi;
using tink.MacroApi;
using StringTools;

class Generator {
  static inline var OUT = '__r';
  public var resolvers:Array<StringAt->StringAt>;
  public function new(?resolvers) 
    this.resolvers = switch resolvers {
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
              function liftAsFunction(wrapped:Expr) {
                var ct = t.toComplex();
                return (
                  function () return
                    if (!value.is(ct) && wrapped.is(ct)) wrapped
                    else value
                ).bounce();
              }            
              switch t {
                case TAbstract(_.get() => { pack: ['tink', 'core'], name: 'Callback' }, [_]):
                  liftAsFunction(macro function (event) $value);
                case TFun([_], _.getID() => 'Void'):
                  liftAsFunction(macro function (event) $value);
                case TFun([], _.getID() => 'Void'):
                  liftAsFunction(macro function () $value);
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

    switch tag.args {
      case PlainArg(t):
        if (n.children != null) 
          tag.name.pos.error('children not allowed on <${tag.name.value}/>');
        switch n.attributes {
          case [Splat(e)]:
            return plain(tag.name, tag.isClass, e, pos);
          default: 
            tag.name.pos.error('<${tag.name.value}/> must have exactly one spread and no other attributes');
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
              pos: tag.name.pos,
              name: tag.name.value,
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
        Some(makeChildren(v, children.toComplex()));
    }, fields);

    var attrType = fieldsType.toComplex();

    var obj = 
      mergeParts(
        mangled.attrs, 
        splats,
        function (name) return switch fields[name] {
          case null: Failure(new Error('Superflous field `$name`'));
          case f: Success(Some(f.type));
        },
        attrType
      );

    return instantiate(tag.name, tag.isClass, key, obj, mangled.children);
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
        var body = makeChildren.bind(n.children, ret.toComplex()).bounce();
        switch [requiredArgs.length, declaredArgs.length] {
          case [1, 0]:
            var ct = requiredArgs[0].t.toComplex();
            macro @:pos(n.name.pos) function (__data__:$ct) {
              tink.Anon.splat(__data__);
              return $body;
            }
          case [l, l2] if (l == l2):
            body.func([for (i in 0...l) { 
              name: declaredArgs[i].value, 
              type: requiredArgs[0].t.toComplex(),
            }]).asExpr();
            //throw 'not implemented';
          case [l1, l2]:
            if (l2 > l1) declaredArgs[l1].pos.error('too many arguments');
            else n.name.pos.error('not enough arguments');
        }
        
      default: 
        makeChildren(n.children, switch t {
          case Some(t): t.toComplex();
          default: n.name.pos.makeBlankType();
        });
    };    
  }

  function getTag(name:StringAt):Tag {

    function anon(anon:AnonType, t, lift:Bool, children:Type) {
      var fields = [for (f in anon.fields) f.name => f];
      
      var childrenAreAttribute = fields.exists('children');
      
      if (childrenAreAttribute) {
        if (children == null) 
          children = fields['children'].type;
        else 
          name.pos.error('tag requires child list and children attribute');
      }
      return 
        if (children == null)
          JustAttributes(fields, t);
        else
          Full(fields, t, children, childrenAreAttribute);
    }

    function mk(t:Type, ?children:Type, isClass:Bool, name):Tag
      return {
        name: name,
        isClass: isClass,
        args: switch t.reduce() {
          case TAnonymous(a):
            anon(a.get(), t, false, children);
          default:
            PlainArg(t);
        }
      }

    function makeFrom(name:StringAt, type:Type)
      return 
        switch type {
          case TFun([{ t: a }, { t: c }], _): 
            return mk(a, c, false, name);
          case TFun([{ t: a }], _): 
            return mk(a, false, name);              
          case v: 
            return switch '${name.value}.new'.resolve(name.pos).typeof() {
              case Success(TFun([{ t: a }, { t: c }], _)):
                mk(a, c, true, name);
              case Success(TFun([{ t: a }], _)):
                mk(a, true, name);
              default:
                name.pos.error('${name.value} has type $v which is unsuitable for HXX');
            }
        }

    switch typeof(name) {
      case Success(t): 
        return makeFrom(name, t);
      case Failure(e):
        for (r in resolvers) {
          var name = r(name);
          switch typeof(name) {
            case Success(t):
              return makeFrom(name, t);
            default:
          }
        }
        return e.throwSelf();
    }
  }

  function typeof(name:StringAt)
    return name.value.resolve(name.pos).typeof();

  function makeChildren(c:Children, ct:ComplexType)
    return
      macro @:pos(c.pos) {
        var $OUT = [];
        ($i{OUT} : $ct);
        ${flatten(c)};
        $i{OUT};
      }

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
      case CNode(n): yield(node.bind(n, c.pos).bounce(c.pos));
      case CSwitch(target, cases): 
        ESwitch(target, [for (c in cases) {
          values: c.values,
          guard: c.guard,
          expr: flatten(c.children)
        }], null).at(c.pos);
      case CIf(cond, cons, alt): 
        macro @:pos(c.pos) if ($cond) ${flatten(cons)} else ${if (alt == null) emptyElse() else flatten(alt)};
      case CFor(head, body): 
        macro @:pos(c.pos) for ($head) ${flatten(body)};
    }

  function emptyElse()
    return macro null;

  function normalize(children:Array<Child>) 
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

  public function root(root:Children):Expr
    return switch root.value {
      case []: root.pos.error('Empty HXX');
      case [v]: macro @:pos(root.pos) {
        var $OUT = [];
        ${child(v, this.root)};
        $i{OUT}[0];
      }
      case v: v[1].pos.error('Only one element allowed here');
    }

}

enum TagArgs {
  PlainArg(t:Type);
  JustAttributes(fields:Map<String, ClassField>, fieldsType:Type);
  Full(fields:Map<String, ClassField>, fieldsType:Type, children:Type, childrenAreAttribute:Bool);
}

typedef Tag = {
  var isClass(default, never):Bool;
  var args(default, never):TagArgs;
  var name(default, never):StringAt;
}
#end