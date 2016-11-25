package;
import tink.Stringly;

abstract Dummy({ name:String, attr:Dynamic<Stringly>, children:Array<Dummy> }) from { name:String, attr:Dynamic<Stringly>, children:Array<Dummy> } { 

  static public function tag(name:String, attr:Dynamic<Stringly>, ?children:Array<Dummy>):Dummy
    return { name: name, attr: attr, children: children };
  
  @:to function toArray():Array<Dummy>
    return [this];
    
  @:from static public function text(s:String):Dummy
    return tag('--text', { content: s }, null);
  
  macro static public function dom(e) 
    return macro @:pos(e.pos) (
      ${hxx.Parser.parse(e, function (name, attr, children:haxe.ds.Option<haxe.macro.Expr>) 
        return macro Dummy.tag(
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