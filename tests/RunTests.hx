package ;

import deepequal.DeepEqual;
import haxe.PosInfos;
import haxe.unit.TestCase;
import haxe.unit.TestRunner;
import Dummy.*;
import vdom.VDom.*;

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
    
    var foo = tag('foo', { });
    
    assertDeepEqual([tag('test', {}, [text(' test '), foo, text('test'), foo, text(' ')])], dom('  <test> test {foo}test${foo} </test>  '));
    assertDeepEqual([tag('test', {}, [text('  '), text(' ')])], dom('  <test>  <!-- ignore this please --> </test>  '));
    assertDeepEqual([tag('foo', { } ), text(' '), tag('bar', { } ), tag('baz', { } )], dom('<foo /> <bar></bar><baz />'));
    
    assertDeepEqual([tag('test', {}, ['foo'])], dom('<test>foo</test>'));    
    assertDeepEqual([tag('test', {}, [' foo'])], dom('<test> foo</test>'));    
    assertDeepEqual([tag('test', {}, ['foo  '])], dom('<test>foo  </test>'));    
  }
  
  
  static function main() {
    #if (js && !nodejs)
      hxx('
        <div />
      ');
    #end
    
    var r = new TestRunner();
    r.add(new RunTests());
    
    travix.Logger.exit(
      if (r.run()) 0
      else 500
    );
  }
  
}