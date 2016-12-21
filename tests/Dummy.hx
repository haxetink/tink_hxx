package;
import haxe.DynamicAccess;
import tink.Stringly;

abstract Dummy({ name:String, attr:DynamicAccess<Stringly>, children:Array<Dummy> }) from { name:String, attr:Dynamic<Stringly>, children:Array<Dummy> } { 

  static public function tag(name:String, attr:Dynamic<Stringly>, ?children:Array<Dummy>):Dummy
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
        for (key in this.attr.keys())
          ret += ' $key="${this.attr[key]}"';
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
      ${hxx.Parser.parse(e, function (name, attr, children:haxe.ds.Option<haxe.macro.Expr>) 
        return macro @:pos(name.pos) Dummy.tag(
          $v{name.value},
          $attr,
          ${switch children {
            case Some(v): v;
            default: macro null;
          }} 
        )
      )}
        :
      Array<Dummy>
    );
  
}