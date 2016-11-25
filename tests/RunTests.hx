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
  
  function testSimple() {
    assertDeepEqual([tag('test', {})], dom('<test />'));
    assertDeepEqual([tag('test', {})], dom('  <test />'));
    assertDeepEqual([tag('test', {})], dom('<test />  '));
    assertDeepEqual([tag('test', {})], dom('  <test />  '));
    assertDeepEqual([tag('test', {})], dom('  <test/>  '));
    assertDeepEqual([tag('test', {})], dom('  <test / >  '));
    assertDeepEqual([tag('test', {})], dom('  <test></test>  '));
    assertDeepEqual([tag('test', {})], dom('  <test>   </test>  '));
    assertDeepEqual([tag('test', {})], dom('  <test>  <!-- ignore this please --> </test>  '));
    assertDeepEqual([tag('foo', {}), tag('bar', {}), tag('baz', {})], dom('<foo /> <bar></bar><baz />'));
  }
  
  function testWithText() {
    assertDeepEqual([tag('test', {}, ['foo'])], dom('<test>foo</test>'));    
    //assertDeepEqual([tag('test', {}, [' foo'])], dom('<test>foo </test>'));    
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