package ;

import deepequal.DeepEqual;
import haxe.PosInfos;
import haxe.unit.TestCase;
import haxe.unit.TestRunner;
import Dummy.*;

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
    var foo = tag('foo', { });
    
    assertDeepEqual([tag('test', {}, [text(' test '), foo, text('test'), foo, text(' ')])], dom('  <test> test {foo}test${foo} </test>  '));
    assertDeepEqual([tag('test', {}, [text('  '), text(' ')])], dom('  <test>  <!-- ignore this please --> </test>  '));
    assertDeepEqual([tag('foo', { } ), text(' '), tag('bar', { } ), tag('baz', { } )], dom('<foo /> <bar></bar><baz />'));
    
    assertDeepEqual([tag('test', {}, ['foo'])], dom('<test>foo</test>'));    
    assertDeepEqual([tag('test', {}, [' foo'])], dom('<test> foo</test>'));    
    assertDeepEqual([tag('test', {}, ['foo  '])], dom('<test>foo  </test>'));    
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