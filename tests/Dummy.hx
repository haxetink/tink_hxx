package;

#if macro
import haxe.macro.Expr;
using tink.MacroApi;
#end
import haxe.DynamicAccess;

abstract AttrVal(String) from String to String {
  @:from static function ofBool(b:Bool):AttrVal
    return if (b) "" else null;
}

@:forward
abstract Dummy({ name:String, attr:DynamicAccess<AttrVal>, children:Children }) from { name:String, attr:Dynamic<AttrVal>, children:Children } {

  static public function tag(name:String, attr:Dynamic<AttrVal>, ?children:Children):Dummy
    return { name: name, attr: attr, children: children };

  public function format():String
    return switch this.name {
      case '--text':
        this.attr['content'];
      case '':
        var ret = '';
        for (c in this.children)
          ret += c.format();
        ret;
      case v:
        var ret = '<$v';
        var keys = [for (key in this.attr.keys()) key];
        keys.sort(Reflect.compare);
        for (key in keys)
          ret += switch this.attr[key] {
            case null: '';
            case '': ' $key';
            case v: ' $key="$v"';
          }
        ret += '>';
        if (this.children != null)
          for (c in this.children)
            ret += c.format();
        ret + '</$v>';
    }


  @:to function toArray():Children
    return [this];

  @:from static public function ofArray(a:Children)
    return tag('', { }, a);

  @:from static public function text(s:String):Dummy
    return tag('--text', { content: s }, null);

  @:from static public function int(i:Int):Dummy
    return text(Std.string(i));

  macro static public function dom(e) {
    var gen = new DummyGen();
    return
      gen.root(
        tink.hxx.Parser.parseRoot(
          e,
          {
            defaultExtension: 'hxx',
            isVoid: function (s) return switch s.value {
              case 'img': true;
              default: false;
            },
            treatNested: gen.root
          }
        )
      );
  }
}

@:pure
abstract Children(Array<Dummy>) from Array<Dummy> {
  public var length(get, never):Int;
    inline function get_length()
      return if (this == null) 0 else this.length;

  @:arrayAccess public inline function get(index:Int)
    return if (this == null) null else this[index];

  @:from static function ofSingle(r:Dummy):Children
    return [r];

  public function concat(that:Array<Dummy>):Children
    return if (this == null) that else this.concat(that);

  public function prepend(r:Dummy):Children
    return switch [this, r] {
      case [null, null]: null;
      case [v, null]: v;
      case [null, v]: v;
      case [a, b]: [b].concat(a);
    }

  public function append(r:Dummy):Children
    return switch [this, r] {
      case [null, null]: null;
      case [v, null]: v;
      case [null, v]: v;
      case [a, b]: a.concat([b]);
    }

}

#if macro
class DummyGen extends tink.hxx.Generator {
  var childrenType = haxe.macro.ComplexTypeTools.toType(macro : Dummy.Children);

  override function node(n:tink.hxx.Node, pos:Position) {
    var attr:Array<tink.anon.Macro.Part> = [],
        splats = [];

    for (a in n.attributes)
      switch a {
        case Splat(e):
          splats.push(e);
        case Empty(name):
          attr.push({
            name: name.value,
            pos: name.pos,
            getValue: function (_) return macro @:pos(name.pos) true,
          });
        case Regular(name, value):
          attr.push({
            name: name.value,
            pos: name.pos,
            getValue: function (_) return value,
          });
      }

    var a = tink.anon.Macro.mergeParts(attr, splats, RDynamic(), pos, macro : Dynamic<Dummy.AttrVal>);
    var children =
      switch n.children {
        case null | { value: null | [] }: macro null;
        case v: childList(v, childrenType);
      }

    return macro @:pos(pos) Dummy.tag($v{n.name.value}, $a, $children);
  }
}
#end