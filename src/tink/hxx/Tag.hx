package tink.hxx;

#if macro
import tink.anon.Macro;
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr;

using haxe.macro.Tools;
using tink.CoreApi;
using tink.MacroApi;
using StringTools;

@:structInit class Tag {

  public var name(default, null):String;
  public var realPath(default, null):String;
  public var create(default, null):TagCreate;
  public var args(default, null):TagArgs;
  public var isVoid(default, null):Bool;
  public var hxxMeta(default, null):Map<String, Type>;

  public var parametrized(default, null):Void->{
    var children(default, never):Type;
    var fieldsType(default, null):ComplexType;
    var requiredFields(default, null):RequireFields;
  }

  static function startsCapital(s:String)
    return s.charAt(0).toUpperCase() == s.charAt(0);

  static final cache = new Map();

  static public function resolve(name:StringAt):Tag {
    var te = Context.typeExpr(name.value.resolve(name.pos));

    var params = [],
        t = te.t;

    var key = switch te.expr {
      case TLocal(v): 'local_${v.id}';// I hope this is unique
      case TTypeExpr(e):
        'type_' + switch e {
          case TTypeDecl(d): d.get().type.toString();
          case TEnumDecl(_.toString() => s)
            | TAbstract(_.toString() => s)
            | TClassDecl(_.toString() => s): s;
        }
      case TField(_, fa):
        function id(cl:haxe.macro.Type.Ref<ClassType>, params:Array<Type>)
          return cl.toString() + switch params {
            case []: '';
            case v: '<' + [for (t in v) t.toString()].join(',') +  '>';
          }
        switch fa {
          case FEnum(e, f):
            params = f.params;
            t = f.type;
            'enum_${e.toString()}.${f.name}';
          case FStatic(c, _.get() => f):
            params = f.params;
            t = f.type;
            'static_${c.toString()}.${f.name}';
          case FAnon(_) | FDynamic(_):
            te.t.toString();
          case FClosure(owner, _.get() => f):
            params = f.params;
            t = f.type;
            'inst_${id(owner.c, owner.params)}.${f.name}';
          case FInstance(cl, params, f):
            'inst_${id(cl, params)}.${f.toString()}';
        }
      default: te.t.toString();// ewwww
    }

    return switch cache[key] {
      case null: cache[key] = declaration(name.value, te, t, params);
      case v: v;
    }
  }

  static function makeArgs(pos:Position, name:String, t:Type, ?children:Type):TagArgs & { children:Type } {
    function anon(anon:AnonType, t, lift:Bool, children:Type):TagArgs & { children:Type } {
      var fields = new Map(),
          aliases = new Map(),
          custom:Array<CustomAttr> = [];

      var childrenAttr = null;

      function setChildrenAttr(f:ClassField)
        if (childrenAttr == null)
          childrenAttr = f;
        else
          f.pos.error('only one field may act as children (${childrenAttr.name} already does)');

      for (f in anon.fields) {

        fields[f.name] = f;

        if (f.meta.has(':children') || f.meta.has(':child'))
          setChildrenAttr(f);

        for (tag in f.meta.extract(':hxx'))
          for (expr in tag.params)
            aliases[expr.getName().sure()] = f.name;

        for (tag in f.meta.extract(':hxxCustomAttributes'))
          for (expr in tag.params)
            switch expr.expr {
              case EConst(CRegexp(pat, opt)):
                custom.push({
                  type: f.type.toComplex({ direct: true }),
                  group: if (f.name == '') None else Some(f.name),
                  filter: new EReg(pat, opt),
                });
              default: expr.reject('regex expected');
            }
      }

      switch fields['children'] {
        case null:
        case v: setChildrenAttr(v);
      }

      var childrenAreAttribute = childrenAttr != null;

      if (childrenAreAttribute) {
        if (children == null)
          children = childrenAttr.type;
        else
          pos.error('$name cannot have both child list and children attribute');
      }

      return {
        aliases: aliases,
        fields: fields,
        fieldsType: t,
        childrenAttribute: if (childrenAreAttribute) childrenAttr.name else null,
        children: children,
        custom: custom,
      }
    }

    #if (haxe_ver < 4.2) //TODO: without this typedeffing, compile time explodes in older haxe versions
    if (!Context.defined('display')) {
      var alias = '';

      function get()
        return Context.getType('tink.hxx.tmp.$alias');

      while (true) {
        alias = 'Attr' + MacroApi.tempName();
        try get()
        catch (e:Dynamic) break;
      }

      Context.defineType({
        pos: pos,
        name: alias,
        pack: ['tink', 'hxx', 'tmp'],
        fields: [],
        kind: TDAlias(t.toComplex()),
      });

      t = get();
    }
    #end

    return
      switch t.reduce() {
        case TAnonymous(a):
          anon(a.get(), t, false, children);
        default:
          pos.error('First argument of $name must be an anonymous object for it to be usable as tag');
      }
  }

  static public inline var DELEGATE = ':hxx.delegate';
  static public inline var DISALLOW = ':hxx.disallow';

  static function specialMeta<T:BaseType>(r:haxe.macro.Type.Ref<BaseType>) {
    var meta = r.get().meta;

    function getSingle(name)
      return
        switch meta.extract(name) {
          case []: None;
          case [v]: Some(v);
          case v: v[1].pos.error('Multiple @$name directives');
        }

    return switch getSingle(DISALLOW) {
      case Some(v):
        Some(Failure(switch v.params {
          case []: '';
          case [v]: v.getString().sure();
          case v: v[1].reject('cannot have more than one argument here');
        }));
      case None:
        switch getSingle(DELEGATE) {
          case Some({ params: [e = macro ($_:$ct)] }):
            var t = e.pos.getOutcome(ct.toType());
            Some(Success({ type: t, path: t.getID() }));
          case Some(m):
            m.pos.error('@$DELEGATE must have one ECheckType argument');
          case None: None;
        }
    }
  }

  static function declaration(name:String, te:Position, type:Type, params:Array<TypeParameter>, ?isVoid:Bool):Tag {
    function mk(args, create, callee, params:Array<TypeParameter>, ?realPath):Tag {
      if (false)
        TFun(args, null);//force inference

      if (realPath == null)
        realPath = name;
      var children = null;

      function reject(reason):Dynamic
        return pos.error('$name is not suitable as a hxx tag, because $reason');

      args = args.copy();

      switch args[args.length - 1] {
        case null:
          reject('it accepts no arguments');
        case nfo if (nfo.t.getID(false) == 'haxe.PosInfos'):
          if (!nfo.opt)
            reject('trailing argument ${nfo.name}:haxe.PosInfos is not optional');
          args.pop();
        default:
      }

      var hxxMeta =
        switch args[0] {
          case { name: 'hxxMeta', t: t }:
            args.shift();
            [for (f in t.getFields().sure()) f.name => f.type];
          default: new Map();
        }

      var attr = switch args.shift() {
        case null: reject('accepts no attributes');
        case a: a.t;
      }

      switch args {
        case []:
        case [a]: children = a.t;
        default: reject('defines too many arguments');
      }

      var args = makeArgs(pos, name, attr, children);
      for (keys in [args.aliases.keys(), args.fields.keys()])
        for (k in keys)
          if (hxxMeta.exists(k))
            reject('conflict between hxx meta argument $k and attribute key');

      if (isVoid && args.children != null)
        pos.error('Tag declared void, but has children');

      return {
        create: create,
        hxxMeta: hxxMeta,
        args: args,
        name: name,
        realPath: realPath,
        isVoid: isVoid,
        parametrized: switch params {
          case []:
            var ret = {
              fieldsType: args.fieldsType.toComplex({ direct: true }),
              requiredFields: RStatic(Macro.fieldsToInfos(args.fields)),
              children: args.children,
            }
            function () return ret;
          default:
            function () {
              var monos = [for (t in params) Context.typeof(macro cast null)];
              var ct = args.fieldsType.reduce().applyTypeParameters(params, monos).toComplex({ direct: true });
              var placeholder = macro (cast null : $ct);
              return {
                fieldsType: ct,
                children: switch args.children {
                  case null: null;
                  case t: t.applyTypeParameters(params, monos);
                },
                requiredFields: RStatic(Macro.fieldsToInfos(
                  args.fields,
                  function (f) {
                    var name = f.name;
                    return Context.typeof(macro $placeholder.$name);
                  }
                ))
              }
            }
        }
      }
    }

    function fromType(type:Type, ?realPath:String)
      return switch type.reduce() {
        case TEnum(specialMeta(_) => Some(o), _)
            | TInst(specialMeta(_) => Some(o), _)
            | TAbstract(specialMeta(_) => Some(o), _):

          switch o {
            case Success(d):
              fromType(d.type, d.path);
            case Failure(v):
              pos.error('Using ${type.toString()} from HXX is not allowed' + switch v {
                case null | '': '';
                default: ', because $v';
              });
          }

        case TInst(cl, _) | TAbstract(_.get().impl => cl, _) if (cl != null):
          var cl = cl.get();

          if (!cl.isPrivate) name = if (cl.module.endsWith(cl.name)) cl.module else '${cl.module}.${cl.name}';

          var options = [FromHxx, New],
              ret = null,
              isAbstract = cl.kind.match(KAbstractImpl(_));

          function getCtor()
            return
              if (isAbstract) cl.findField('_new', true);
              else cl.constructor.get();

          function yield(f:ClassField, kind)
            return
              switch f.type.reduce() {
                case TFun(args, _):
                  mk(args, kind, '$name.$kind', if (kind == New && !isAbstract) cl.params.concat(f.params) else f.params, realPath);
                case v:
                  throw 'assert $v';
              }
          switch cl.findField('fromHxx', true) {
            case null:
              switch getCtor() {
                case null:
                  pos.error(
                    if (cl.statics.get().length + cl.fields.get().length == 0)
                      'There seems to be a type error in $name that cannot be reported due to typing order. Please import the type explicitly or compile it separately.'
                    else
                      'type $name does not define a suitable constructor of static fromHxx method to be used as HXX'
                  );
                case v:
                  yield(v, New);
              }
            case v:
              yield(v, FromHxx);
          }
        case TMono(_.get() => null) if (Context.defined('display')):
          pos.error('unknown tag $name');
        default:
          pos.error('$name has type ${type.toString()} which is unsuitable for HXX');

      }

    function hasField(name) {
      for (f in type.getFields(false).sure())
        if (f.name == name)
          return true;
      return false;
    }

    function instanceMethod()
      return
        switch Context.typeof(macro @:pos(pos) ${name.resolve()}.fromHxx).reduce() {
          case TFun(args, _):
            mk(args, Call, name, params, '$name.fromHxx');
          case v:
            pos.error('$name.fromHxx should be a function, but it is a ${v.toString()}');
        }

    var orig = type;

    while (true)
      switch type {
        case TType(_.get() => { pack: [], name: t }, []) if (t.startsWith('Class<') || t.startsWith('Enum<')):
          return fromType(Context.getType(name));
        case TFun(args, _):
          return mk(args, Call, name, params);
        case TLazy(_) | TType(_):
          type = type.reduce(true);
        case TInst(_) | TAnonymous(_) if (hasField('fromHxx')):
          return instanceMethod();
        case TAbstract(_.get().impl => cl, _) if (cl != null && cl.get().findField('fromHxx', true) != null):
          return instanceMethod();
        default:
          pos.error('$name has type ${orig.toString()} which is unsuitable for HXX');
      }
  }
}

typedef TagArgs = {
  var aliases(default, never):Map<String, String>;//TODO: consider putting aliases straight into fields
  var fields(default, never):Map<String, ClassField>;
  var fieldsType(default, never):Type;
  var childrenAttribute(default, never):Null<String>;
  var custom(default, never):Array<CustomAttr>;
}

typedef CustomAttr = {
  var filter(default, never):EReg;
  var group(default, never):Option<String>;
  var type(default, never):ComplexType;
}

@:enum abstract TagCreate(String) to String {
  var Call = "call";
  var New = "new";
  var FromHxx = "fromHxx";
}
#end
