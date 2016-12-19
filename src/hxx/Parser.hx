package hxx;

import haxe.macro.Expr;
import hxx.Generator;
import tink.parse.Char.*;
import tink.parse.ParserBase;
import tink.parse.StringSlice;
import haxe.macro.Context;

using StringTools;
using tink.MacroApi;
using tink.CoreApi;

class Parser extends ParserBase<Position, haxe.macro.Error> { 
  
  var gen:Generator;
  var fileName:String;
  var offset:Int;
  
  public function new(fileName:String, source:String, offset:Int, gen:Generator) {
    this.fileName = fileName;
    this.gen = gen;
    this.offset = offset;
    
    super(source);
  }
  
  function withPos(s:StringSlice, ?transform:String->String):StringAt {
    return {
      pos: doMakePos(s.start, s.end),
      value: switch transform {
        case null: s.toString();
        case v: v(s);
      },
    }
  }
  
  function parseExpr(source, pos)
    return Context.parseInlineString(source, pos);
  
  function injectedExpr() {
    var start = pos;
    var expr = null;
    do {
      upto('}');
      
      var inner = withPos(source[start...pos-1]);
      
      if (inner.value.split('{').length == inner.value.split('}').length)
        expr = parseExpr(inner.value, inner.pos);
    } while (expr == null);
    
    return expr;      
  }
  
  function parseChild() {
    var name = withPos(ident(true).sure());
    var hasChildren = true;
    var attrs = new Array<NamedWith<StringAt, Expr>>();
    
    while (!allow('>')) {
      if (allow('/')) {
        expect('>');
        hasChildren = false;
        break;
      }
      
      if (allow('{')) {
        var pos = pos;
        if (allow('...'))
          die('spread not implemented', pos...this.pos);
          
        die('unexpected {');
      }
      var attr = withPos(ident().sure());
      expect('=');
      
      attrs.push(
        new NamedWith(
          attr,
          if (allow('{') || allow("${")) 
            injectedExpr();
          else             
            EConst(CString(expect('"') + upto('"').sure().toString().urlDecode())).at(doMakePos(source.start, source.end))
        )
      );
    }
    
    return
      gen.makeNode(name, attrs, if (hasChildren) parseChildren(name.value) else []);
  }
  
  function parseChildren(?closing:String):Array<Expr> {
    var ret = [];      
    
    while (pos < max) {
      
      function text(upto) {
        switch gen.string(withPos(this.source[pos...upto], StringTools.htmlUnescape)) {
          case Some(v): ret.push(v);
          case None:
        }
        pos = upto;
      }
      
      switch [source.indexOf('{', pos), source.indexOf('<', pos)] {
        case [-1, -1]:
          this.skipIgnored();
          if (this.pos < this.max)
            die('< expected');
        
        case [first, later] if (first != -1 && (first < later || later == -1)):
          
          if (String.fromCharCode(source[first - 1]) == '$')
            first--;
          
          text(first);
          
          if (!(allowHere("{") || allowHere("${")))
            throw 'assert';
            
          ret.push(injectedExpr());
          
        case [_, v]:
          text(v);
          expectHere('<');
          if (allowHere('!--')) 
            upto('-->', true);
          else if (allowHere('!'))
            die('Invalid comment or unsupported processing instruction');
          else if (allowHere('/')) {
            var found = ident(true).sure();
            expectHere('>');
            if (found != closing)
              die('found </$found> but expected </$closing>', found.start...found.end);
            return ret;
          }
          else {
            ret.push(parseChild());        
          }
      }
            
    }
    
    if (closing != null)
      die('unclosed <$closing>');
    
    return ret;
  }
  
  static var IDENT_START = UPPER || LOWER || '_'.code;
  static var IDENT_CONTD = IDENT_START || DIGIT;
  
  function ident(here = false) 
    return 
      if ((here && is(IDENT_START)) || (!here && upNext(IDENT_START)))
        Success(readWhile(IDENT_CONTD));
      else 
        Failure(makeError('Identifier expected', makePos(pos)));  
  
  override function doMakePos(from:Int, to:Int):Position
    return 
      #if macro Context.makePosition #end ({ min: from + offset, max: to + offset, file: fileName });
  
  override function makeError(message:String, pos:Position)
    return 
      new haxe.macro.Expr.Error(message, pos);
  
  override function doSkipIgnored() {
    doReadWhile(WHITE);
    
    if (allow('//'))
      doReadWhile(function (c) return c != 10);
      
    if (allow('/*'))
      upto('*/').sure();
      
    if (allow('#if')) {
      throw 'not implemented';
    }
  }  
  
  static public function parse(e:Expr, gen:Generator) {
    var s = e.getString().sure();
    var pos = Context.getPosInfos(e.pos);
    return gen.root(new Parser(pos.file, s, pos.min + 1, gen).parseChildren());
  }
}