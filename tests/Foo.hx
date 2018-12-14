@:fromHxx(transform = Foo.parse)
class Foo {
  var s:String;
  function new(s)
    this.s = s;

  public function toString()
    return 'Foo($s)';
  static public function parse(s:String):Foo
    return new Foo(s);
}