package ;

import deepequal.DeepEqual.*;
import tink.unit.*;
import tink.testrunner.*;
import Dummy.*;
import Tags.*;

@:asserts
class RunTests {
  public function new() {}
  
  public function whitespace() {
    asserts.assert(compare(tag('test', {}), dom('<test />')));
    asserts.assert(compare(tag('test', {}), dom('  <test />')));
    asserts.assert(compare(tag('test', {}), dom('<test />  ')));
    asserts.assert(compare(tag('test', {}), dom('  <test />  ')));
    asserts.assert(compare(tag('test', {}), dom('  <test/>  ')));
    asserts.assert(compare(tag('test', {}), dom('  <test / >  ')));
    asserts.assert(compare(tag('test', {}), dom('  <test></test>  ')));
    asserts.assert(compare(tag('test', { }, [text('   ')]), dom('  
    <test>   </test>  ')));
    
    var numbers = [for (i in 0...100) i];
    
    asserts.assert(compare(
      tag('div', {}, [for (i in 0...4) tag('button', {}, [i])]),
      dom('
        <div>
          {import "test"}
          {import "test.hxx"}
          {import "./tests/test"}
          {import "./tests/test.hxx"}
        </div>
      ')
    ));
    var foo = tag('foo', { } );
    
    dom('{import "test"}');
    
    asserts.assert(compare(tag('test', {}, [text(' test '), foo, text('test'), foo, text(' ')]), dom('  <test> test {foo}test${foo} </test>  ')));
    asserts.assert(compare(tag('test', {}, [text('  '), text(' ')]), dom('  <test>  <!-- ignore this please --> </test>  ')));
    asserts.assert(compare([tag('foo', { } ), text(' '), tag('bar', { } ), tag('baz', { } )], dom('<wrap><foo /> <bar></bar><baz /></wrap>').children));
    
    asserts.assert(compare(tag('test', {}, ['foo']), dom('<test>foo</test>')));
    asserts.assert(compare(tag('test', {}, [' foo']), dom('<test> foo</test>')));
    asserts.assert(compare(tag('test', {}, ['foo  ']), dom('<test>foo  </test>')));
    asserts.assert('<div foo.bar="123"></div>' == dom('<div foo.bar="123" />').format());
    return asserts.done();
  }

  public function splat() {
    var o1 = { foo: 'o1', bar: '123' };
    var o2 = { foo: 'o2', baz: 'o2' };
    var one = '1';
    asserts.assert('<div bar="32$one" baz="o2" foo="o1"></div>' == dom('
      <div bar="321" {...o1} ${...o2} />
    ').format());
    return asserts.done();
  }

  public function let() {
    var o1 = { foo: 'o1', bar: '42' };
    asserts.assert(
      '<div>${o1.foo} ${o1.bar} 123</div>' ==
      dom('<let baz={123} {...o1}>
        <div>{foo} {bar} {baz}</div>
      </let>').format()
    );
    return asserts.done();
  }
  
  public function control() {
    var other = dom('<other/>');
    asserts.assert('<div><zero></zero><one></one><two></two><other></other><other></other></div>' == dom('
      <div>
        <for {i in 0...5}>
          <if {i == 0}>
            <zero />
          <else if ${i == 1}>
            <one />
          <elseif {i == 2}>
            <two />
          <else>
            ${other}        
          </if>
        </for>
      </div>
    ').format());
    asserts.assert('<div><zero></zero><one></one><two></two><other></other><other></other></div>' == dom('
      <div>
        <for {i in 0...5}>
          <switch $i>
            <!-- <case {whatever} -->
            <case {0}>
              <zero />
            <case {1}>
              <one />
            <case {v} if {v == 2}>
              <two />
            <case {_}>
              $other
          </switch>
        </for>
      </div>
    ').format());
    
    return asserts.done();
  }

  public function customCast() {
    function table(attr:{ foo: Foo })
      return attr.foo;

    asserts.assert('Foo(blargh)' == Plain.hxx('<table foo="blargh" />').toString());
    return asserts.done();
  }

  public function childrenAttribute() {
    function foo(attr:{ @:children var bar:String; })
      return attr.bar;

    asserts.assert('yohoho' == Plain.hxx('<foo>yohoho</foo>'));
    return asserts.done();
  }

  public function localTags() {
    
    function blub(attr:{ function hoho(attr:{ function woooosh(attr:{ foo:Int }):String; }):Array<String>; }) 
      return attr.hoho({ woooosh: function (o) return [for (i in 0...o.foo) 'x'].join('') });

    var arr = Plain.hxx('
      <blub>
        <hoho>
          <woooosh foo={5} />
          <woooosh foo={3} />
        </hoho>
      </blub>
    ');

    asserts.assert(arr.join(',') == 'xxxxx,xxx');

    return asserts.done();
  }

  public function dotPaths() {
    function identity(x)
      return x;

    var o = { foo: { x: 3, y: 4 }, bar: "yolo", deep: { a: { b: { c: "d" }}}};

    identity(o);

    asserts.assert(compare(o, Plain.hxx('<identity foo.x={3} foo.y={4} bar="yolo" deep.a.b.c="d" />')));

    return asserts.done();    
  }

  #if haxe4
  
  public function inlineMarkup() {
    var a = [for (i in 0...10) '$i'];
    
    #if tink_parse_unicode
    NonSense.showOff();
    #end

    Plain.hxx(
      <div>
        {a.map(x -> <div>{x}</div>)}
      </div>
    );
    return asserts.done();
  }
  #end
  
  static function main() {
    
    Runner.run(TestBatch.make([
      new RunTests(),
    ])).handle(Runner.exit);
  }
  
}