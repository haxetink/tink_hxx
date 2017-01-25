package tink.hxx;

import haxe.macro.Expr;
import tink.hxx.Generator;
import tink.parse.Char.*;
import tink.parse.ParserBase;
import tink.parse.StringSlice;
import haxe.macro.Context;

using StringTools;
using haxe.io.Path;
using tink.MacroApi;
using tink.CoreApi;

typedef ParserConfig = {
  defaultExtension:String,
  ?defaultSwitchTarget:Expr,
  ?noControlStructures:Bool,
  ?interceptTag:String->Option<StringAt->Expr>,
}

class Parser extends ParserBase<Position, haxe.macro.Error> { 
  
  var gen:Generator;
  var fileName:String;
  var offset:Int;
  var config:ParserConfig;
  
  
  public function new(fileName, source, offset, gen, config) {
    this.fileName = fileName;
    this.gen = gen;
    this.offset = offset;
    this.config = config;
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
    return 
      try Context.parseInlineString(source, pos)
      catch (e:haxe.macro.Error) throw e
      catch (e:Dynamic) pos.error(e);
  
  function simpleIdent() {
    var name = withPos(ident(true).sure());
    return macro @:pos(name.pos) $i{name.value};
  }
    
  function argExpr()
    return 
      if (allow("${") || allow('{')) 
        Success(ballancedExpr('{', '}'));
      else if (allow("$")) 
        Success(simpleIdent());
      else 
        Failure(makeError('expression expected', makePos(pos, pos)));
    
  function ballancedExpr(open:String, close:String) {
    var src = ballanced(open, close);
    return parseExpr(src.value, src.pos);
  }
  
  function ballanced(open:String, close:String) {
    var start = pos;
    var ret = null;
    do {
      upto(close);
      
      var inner = withPos(source[start...pos-1]);
      
      if (inner.value.split(open).length == inner.value.split(close).length)
        ret = inner;
    } while (ret == null);
    
    return ret;          
  }
  
  function kwd(name:String) {
    if (config.noControlStructures) return false;
    var pos = pos;
    var isIf = isNext('if');
    
    var found = switch ident(true) {
      case Success(v) if (v == name): true;
      default: false;
    }
    
    if (!found) this.pos = pos;
    return found;
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
        
        if (allow('...')) {
          attrs.push(new NamedWith({ pos: makePos(pos, this.pos), value: '...' }, ballancedExpr('{', '}') ));
          continue;
        }
        die('unexpected {');
      }
      var attr = withPos(ident().sure());
        
      expect('=');
      
      attrs.push(
        new NamedWith(
          attr,
          switch argExpr() {
            case Success(e): e;
            default:
              var s = parseString();
              EConst(CString(s.value)).at(s.pos);
          }
        )
      );
    }
    
    return
      gen.makeNode(name, attrs, if (hasChildren) parseChildren(name.value) else []);
  }
  
  function parseString()
    return expect('"') + withPos(upto('"').sure(), StringTools.urlDecode);
  
  function parseChildren(?closing:String):Array<Expr> {
    var ret = [];      
    
    while (pos < max) {
       
      
      function text(slice) {
        switch gen.string(withPos(slice, StringTools.htmlUnescape)) {
          case Some(v): ret.push(v);
          case None:
        }
      }
      
      switch first(["${", "$", "{", "<"], text) {
        case Success("<"):
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
          else if (kwd('for')) {
            var head = argExpr().sure() + expect('>');
            ret.push(gen.flatten(head.pos, [macro for ($head) ${gen.flatten(head.pos, parseChildren('for'))}]));
          }
          else if (kwd('switch')) 
            ret.push(parseSwitch());
          else if (kwd('if')) 
            ret.push(parseIf());
          else if (kwd('else')) 
            throw new Else(ret, false);
          else if (kwd('elseif')) 
            throw new Else(ret, true);
          else if (kwd('case')) 
            throw new Case(ret);
          else 
            ret.push(parseChild());        
          
        case Success("$"):
          
          ret.push(simpleIdent());
          
        case Success(v):
          
          if (allow('import')) {
            
            var file = parseString();
            
            expect('}');
                        
            var name = file.value;
            
            if (name.extension() == '')
              name = '$name.${config.defaultExtension}';
                          
            if (!name.startsWith('./'))
              name = Path.join([fileName.directory(), name]);
              
            var content = 
              try
                sys.io.File.getContent(name)
              catch (e:Dynamic)
                file.pos.error(e);
            
            Context.registerModuleDependency(Context.getLocalModule(), name);
                
            var p = new Parser(name, content, 0, gen, config);
            for (c in p.parseChildren())
              ret.push(c);
            
          }
          else
            ret.push(ballancedExpr('{', '}'));
            
        case Failure(e):
          this.skipIgnored();
          if (this.pos < this.max)
            e.pos.error(e.message);
      }
            
    }
    
    if (closing != null)
      die('unclosed <$closing>');
    
    return ret;
  }
  
  function parseSwitch() {
    var target = 
      (switch [argExpr(), config.defaultSwitchTarget] {
        case [Success(v), _]: v;
        case [Failure(v), null]: throw v;
        case [_, v]: v;
      }) + expect('>') + expect('<case');
    
    var cases:Array<haxe.macro.Expr.Case> = [];
    
    var last = false;
    while (!last) {
      var arg = argExpr().sure();
      cases.push({
        values: [arg],
        guard: (if (allow('if')) argExpr().sure() else null) + expect('>'),
        expr:
          try {
            last = true;
            gen.flatten(arg.pos, parseChildren('switch'));
          }
          catch (e:Case) {
            last = false;
            gen.flatten(arg.pos, e.children);
          }
      });
    }
    return ESwitch(target, cases, null).at();
  }
  
  function parseIf() {
    var start = pos;
    var cond = argExpr().sure() + expect('>');
    
    function make(cons, alt) {
      
      var pos = makePos(start, pos);
      
      function posOf(a:Array<Expr>)
        return switch a {
          case []: pos;
          default:
            a[a.length - 1].pos;
        }
      
      var cons = gen.flatten(posOf(cons), cons);
      var alt = gen.flatten(posOf(alt), alt);
      
      return macro @:pos(cond.pos) if ($cond) $cons else $alt;
    }
    return 
      try {
        make(parseChildren('if'), []);
      }
      catch (e:Else) {
        if (e.elseif || switch ident() { case Success(v): if (v == 'if') true else die('unexpected $v', v.start...v.end); default: false; } ) 
          make(e.children, [parseIf()]);
        else
          expect('>') + make(e.children, parseChildren('if'));
      }
  }
  
  static var IDENT_START = UPPER || LOWER || '_'.code;
  static var IDENT_CONTD = IDENT_START || DIGIT || '-'.code || '.'.code;
  
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
  
  static public function parse(e:Expr, gen:Generator, ?config:ParserConfig) {
    if (config == null) 
      config = {
        defaultExtension: 'hxx',
        noControlStructures: false,
      }
      
    var s = e.getString().sure();
    var pos = Context.getPosInfos(e.pos);
    var p = new Parser(pos.file, s, pos.min + 1, gen, config);
    p.skipIgnored();
    return try {
      gen.root(p.parseChildren());
    }
    catch (e:Case) 
      p.die('case outside of switch', p.pos - 4 ... p.pos)
    catch (e:Else)
      p.die('else without if', p.pos - 4 ... p.pos);
  }
}

private class Branch {
  
  public var children(default, null):Array<Expr>;
  
  public function new(children)
    this.children = children;
    
  public function toString() 
    return 'mispaced ${Type.getClassName(Type.getClass(this))}';
}

private class Case extends Branch { 
  
}
private class Else extends Branch { 
  
  public var elseif(default, null):Bool;
  
  public function new(children, elseif) {
    super(children);
    this.elseif = elseif;
  }
  
}
