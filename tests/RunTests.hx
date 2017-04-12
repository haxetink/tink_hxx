package ;

import deepequal.DeepEqual;
import haxe.PosInfos;
import haxe.unit.TestCase;
import haxe.unit.TestRunner;
import Dummy.*;

using StringTools;

class RunTests extends TestCase {

  function assertDeepEqual<A>(a:A, b:A, ?pos:PosInfos) {
    switch DeepEqual.compare(a, b, pos) {
      case Failure(e):
        currentTest.success = false;
        currentTest.posInfos = pos;
        currentTest.error = e.message;
        throw currentTest;
      case Success(_): 
        assertTrue(true);
    }
  }
  
  function test() {
    assertDeepEqual([tag('test', {})], dom('<test />'));
    assertDeepEqual([tag('test', {})], dom('  <test />'));
    assertDeepEqual([tag('test', {})], dom('<test />  '));
    assertDeepEqual([tag('test', {})], dom('  <test />  '));
    assertDeepEqual([tag('test', {})], dom('  <test/>  '));
    assertDeepEqual([tag('test', {})], dom('  <test / >  '));
    assertDeepEqual([tag('test', {})], dom('  <test></test>  '));
    assertDeepEqual([tag('test', { }, [text('   ')])], dom('  <test>   </test>  '));
    
    var numbers = [for (i in 0...100) i];
    
    assertDeepEqual(
      [tag('div', {}, [for (i in 0...4) tag('button', {}, [i])])],
      dom('
        <div>
          {import "test"}
          {import "test.hxx"}
          {import "./tests/test"}
          {import "./tests/test.hxx"}
        </div>
      ')
    );
    var foo = tag('foo', { } );
    
    dom('{import "test"}');
    
    assertDeepEqual([tag('test', {}, [text(' test '), foo, text('test'), foo, text(' ')])], dom('  <test> test {foo}test${foo} </test>  '));
    assertDeepEqual([tag('test', {}, [text('  '), text(' ')])], dom('  <test>  <!-- ignore this please --> </test>  '));
    assertDeepEqual([tag('foo', { } ), text(' '), tag('bar', { } ), tag('baz', { } )], dom('<foo /> <bar></bar><baz />'));
    
    assertDeepEqual([tag('test', {}, ['foo'])], dom('<test>foo</test>'));    
    assertDeepEqual([tag('test', {}, [' foo'])], dom('<test> foo</test>'));    
    assertDeepEqual([tag('test', {}, ['foo  '])], dom('<test>foo  </test>'));   
  }

  function testSplat() {
    var o1 = { foo: 'o1', bar: '123' };
    var o2 = { foo: 'o2', baz: 'o2' };
    assertEquals('<div bar="321" baz="o2" foo="o1"></div>', dom('
      <div bar="321" {...o1} {...o2} />
    ')[0].format());
  }
  
  function testControl() {
    var other = dom('<other/>');
    assertEquals('<div><zero></zero><one></one><two></two><other></other><other></other></div>', dom('
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
    ')[0].format());
    assertEquals('<div><zero></zero><one></one><two></two><other></other><other></other></div>', dom('
      <div>
        <for {i in 0...5}>
          <switch $i>
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
    ')[0].format());
  }
  
  static function main() {
    
    var r = new TestRunner();
    r.add(new RunTests());
    
    travix.Logger.exit(
      if (r.run()) 0
      else 500
    );
  }
  
}