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
    return macro @:pos(e.pos) (
      ${tink.hxx.Parser.parse(
        e, 
        function (name, attr, children:haxe.ds.Option<haxe.macro.Expr>) 
          return
            if (name.value == '...') {
              
              var children = switch children {
                case Some(v): v;
                default: macro [];
              }
              
              macro @:pos(name.pos) Dummy.ofArray($children);
            }
            else
              macro @:pos(name.pos) Dummy.tag(
                $v{name.value},
                ${tink.hxx.Generator.applySpreads(attr, macro tink.hxx.Merge.objects)},
                ${switch children {
                  case Some(v): v;
                  default: macro null;
                }} 
              ),
        {
          defaultExtension: 'hxx',
          isVoid: function (s) return switch s {
            case 'img': true;
            default: false;
          }
        }
      )}
        :
      Array<Dummy>
    );
  
}