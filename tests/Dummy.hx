package;
import haxe.DynamicAccess;

abstract AttrVal(String) from String to String {
  @:from static function ofBool(b:Bool):AttrVal
    return if (b) "" else null;
}

abstract Dummy({ name:String, attr:DynamicAccess<AttrVal>, children:Array<Dummy> }) from { name:String, attr:Dynamic<AttrVal>, children:Array<Dummy> } { 

  static public function tag(name:String, attr:Dynamic<AttrVal>, ?children:Array<Dummy>):Dummy
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
  
    
  @:to function toArray():Array<Dummy>
    return [this];
    
  @:from static public function ofArray(a:Array<Dummy>)
    return tag('', { }, a);
    
  @:from static public function text(s:String):Dummy
    return tag('--text', { content: s }, null);
    
  @:from static public function int(i:Int):Dummy
    return text(Std.string(i));
  
  macro static public function dom(e) 
    return 
      new DummyGen().root(
        tink.hxx.Parser.parseRoot(
          e, 
          {
            defaultExtension: 'hxx',
            isVoid: function (s) return switch s {
              case 'img': true;
              default: false;
            }
          }
        )
      ); 
}

#if macro
class DummyGen extends tink.hxx.Generator {
  override function node(n:tink.hxx.Node, pos:haxe.macro.Expr.Position) {

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
    
    var a = tink.anon.Macro.mergeParts(attr, splats, pos, macro : Dynamic<Dummy.AttrVal>);
    var children = 
      switch n.children {
        case null | { value: null | [] }: macro null;
        case v: makeChildren(v, macro : Dummy);
      }
    return macro @:pos(pos) Dummy.tag($v{n.name.value}, $a, $children);
  }
}
#end