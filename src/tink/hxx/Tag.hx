package tink.hxx;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Expr;

using haxe.macro.Tools;
using tink.CoreApi;
using tink.MacroApi;
using StringTools;

@:structInit class Tag {

  public var name(default, never):String;
  public var create(default, never):TagCreate;
  public var args(default, never):TagArgs;
  public var isVoid(default, never):Bool;  

  static function startsCapital(s:String)
    return s.charAt(0).toUpperCase() == s.charAt(0);

  static public function resolve(localTags:Map<String, Position->Tag>, name:StringAt):Outcome<Tag, Error>
    return switch localTags[name.value] {
      case null: 

        var found = Context.getLocalVars()[name.value];

        if (found == null) {
          var path = name.value.split('.');
          if (path.length > 1 || startsCapital(path[path.length - 1]))
            found = Context.typeof(name.value.resolve(name.pos));
        }

        if (found == null) 
          name.pos.makeFailure('unknown tag <${name.value}>');
        else 
          Success((localTags[name.value] = declaration.bind(name.value, _, found))(name.pos));
      case get: Success(get(name.pos));
    }

  static public function getAllInScope(defaults:Lazy<Array<Named<Position->Tag>>>) {
    var localTags = new Map();
    function add(name:String, type)
      if (name.charAt(0) != '_')//seems reasonable
        localTags[name] = {
          var ret = null;
          function (pos) {//seems I've reimplemented `tink.core.Lazy` here for some reason
            if (ret == null) 
              ret = declaration(name, pos, type);
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
            if (f.kind.match(FMethod(MethNormal | MethInline | MethDynamic))) 
              add(f.name, f.type);
        for (f in statics)
          add(f.name, f.type);

      default:
    }

    function add(name, f)
      if (!localTags.exists(name))
        localTags[name] = f;

    for (i in Context.getLocalImports())
      switch i {
        case { mode: IAll, path: path } if (startsCapital(path[path.length - 1].name)):
          
          path = path.copy();
          
          var e = {
            var first = path.shift();
            macro @:pos(first.pos) $i{first.name};
          }

          for (p in path)
            e = EField(e, p.name).at(p.pos);

          for (t in extractAllFrom(e).get())
            add(t.name, t.value);
        default:
      }

    for (d in defaults.get())
      if (!localTags.exists(d.name)) 
        localTags[d.name] = d.value;
    return localTags;
  } 

  static function makeArgs(pos:Position, name:String, t:Type, ?children:Type):TagArgs {
    function anon(anon:AnonType, t, lift:Bool, children:Type):TagArgs {
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
                  type: f.type.toComplex(),
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

    var alias = MacroApi.tempName();
    
    Context.defineType({//TODO: without this typedef, compile time explodes ... reduce and raise Haxe issue
      pos: pos,
      name: alias,
      pack: ['tink', 'hxx', 'tmp'],
      fields: [],
      kind: TDAlias(t.toComplex()),
    });

    t = Context.getType('tink.hxx.tmp.$alias');
    
    return 
      switch t.reduce() {
        case TAnonymous(a):
          anon(a.get(), t, false, children);
        default:
          pos.error('First argument of $name must be an anonymous object for it to be usable as tag');
      }
  }

  static public function declaration(name:String, pos:Position, type:Type, ?isVoid:Bool):Tag {

    function mk(args, create):Tag {
      TFun(args, null);//force inference
      var children = null;
      var attr = 
        switch args {
          case [{ t: a }, { t: c }]:
            children = c;
            a;
          case [{ t: a }]:
            a;
          default: pos.error('Function $name is not suitable as a hxx tag because it must have 1 or 2 arguments, but has ${args.length} instead');
        }

      var args = makeArgs(pos, name, attr, children);
      if (isVoid && args.children != null)
        pos.error('Tag declared void, but has children');
      return {
        create: create, 
        args: args, 
        name: name,
        isVoid: isVoid,
      };
    }

    return
      switch type.reduce() {
        case TFun(args, _): 
          mk(args, Call);
        default:
          switch Context.getType(name).reduce() {
            case TInst(cl, _) | TAbstract(_.get().impl => cl, _) if (cl != null):
              var cl = cl.get();

              var options = [FromHxx, New],
                  ret = null;

              if (pos.getOutcome(type.getFields()).length == 0) 
                pos.error('There seems to be a type error in $name that cannot be reported due to typing order. Please import the type explicitly or compile it separately.');
              
              for (kind in options)
                switch '$name.$kind'.resolve(pos).typeof() {
                  case Success(_.reduce() => TFun(args, _)):
                    ret = mk(args, kind);
                    break;
                  default: 
                }

              if (ret == null) 
                pos.error('type $name does not define a suitable constructor of static fromHxx method to be used as HXX');
              else ret;
            case TMono(_.get() => null) if (Context.defined('display')):
              pos.error('unknown tag $name');
            default:
              pos.error('$name has type ${type.toString()} which is unsuitable for HXX');
          }
      }  
  }

  static public function extractAllFrom(e:Expr):Lazy<Array<Named<Position->Tag>>> {
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
          case FMethod(MethMacro): continue; //TODO: consider treating these as opaque tags
          case FMethod(_): 
            new Named(
              f.name,{
                var ret = null;
                function (pos) {
                  if (ret == null)
                    ret = declaration('$name.${f.name}', pos, f.type, f.meta.extract(':voidTag').length > 0);
                  return ret;
                } 
              }
              
            );
          default: continue;
        }
      ];
    }
  }

}

typedef TagArgs = {
  var aliases(default, never):Map<String, String>;
  var fields(default, never):Map<String, ClassField>;
  var fieldsType(default, never):Type;
  var children(default, never):Type;
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
