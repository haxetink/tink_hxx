package tink.hxx;

import haxe.macro.Expr;
import tink.hxx.Node;
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
  ?fragment:String,
  ?defaultSwitchTarget:Expr,
  ?noControlStructures:Bool,
  ?isVoid:String->Bool,
  //?interceptTag:String->Option<StringAt->Expr>, <--- consider adding this back
}

class Parser extends ParserBase<Position, haxe.macro.Error> { 
  
  var fileName:String;
  var offset:Int;
  var config:ParserConfig;
  var isVoid:String->Bool;
  
  function new(fileName, source, offset, config) {
    this.fileName = fileName;
    this.offset = offset;
    this.config = config;
    super(source);
    
    function get<T>(o:{ var isVoid(default, null):T; }) return o.isVoid;

    this.isVoid = switch get(config) {
      case null: function (_) return false;
      case v: v;
    }
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
  
  function processExpr(e:Expr) 
    return
      #if tink_syntaxhub
        switch tink.SyntaxHub.exprLevel.appliedTo(new ClassBuilder()) {
          case Some(f): f(e);
          case None: e;
        }
      #else
        e;
      #end

  function parseExpr(source, pos) 
    return
      processExpr( 
        try Context.parseInlineString(source, pos)
        catch (e:haxe.macro.Error) throw e
        catch (e:Dynamic) pos.error(e)
      );

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
      if (!upto(close).isSuccess())
        die('Missing corresponding `$close`', start...start+1);
      
      var inner = withPos(source[start...pos-1]);
      
      if (inner.value.split(open).length == inner.value.split(close).length)
        ret = inner;
    } while (ret == null);
    
    return ret;          
  }
  
  function kwd(name:String) {
    if (config.noControlStructures) return false;
    var pos = pos;
    
    var found = switch ident(true) {
      case Success(v) if (v == name): true;
      default: false;
    }
    
    if (!found) this.pos = pos;
    return found;
  }
  
  function parseChild() return located(function () {
    var fragment = allowHere('>');
    if (fragment && config.fragment == null)
      die('Fragments not supported');
    var name = withPos(
      if (fragment) source[pos-1...pos-1];
      else ident(true).sure()
    );
    
    var hasChildren = true;
    var attrs = new Array<Attribute>();
    
    if (!fragment)
      while (!allow('>')) {
        if (allow('/')) {
          expect('>');
          hasChildren = false;
          break;
        }
        
        if (allow("${") || allow('{')) {        
          if (allow('...')) {
            attrs.push(Splat(ballancedExpr('{', '}')));
            continue;
          }
          die('unexpected {');
        }
        var attr = withPos(ident().sure());
                
        attrs.push(
          if (allow('=')) 
            Regular(attr, switch argExpr() {
              case Success(e): macro @:pos(e.pos) ($e);
              default:
                //TODO: allow numbers here
                var s = parseString();
                EConst(CString(s.value)).at(s.pos);
            })
          else
            Empty(attr)
        );
      }
    
    return CNode({
      name: if (fragment) { value: config.fragment, pos: name.pos } else name,
      attributes: attrs, 
      children: if (hasChildren && !isVoid(name.value)) parseChildren(name.value) else null
    });
  });
  
  function parseString() {
    var end = 
      if (allow("'")) "'";
      else {
        expect('"');
        '"';
      }
    return  withPos(upto(end).sure(), StringTools.htmlUnescape);
  }
  
  function parseChildren(?closing:String):Children {
    var ret:Array<Child> = [],
        start = pos;    

    function result():Children return {
      pos: makePos(start, pos),
      value: ret,
    }  

    function expr(e:Expr)
      ret.push({
        pos: e.pos,
        value: CExpr(e),
      });    

    function text(slice) {
      var text = withPos(slice, StringTools.htmlUnescape);
      if (text.value.length > 0)
        ret.push({
          pos: text.pos,
          value: CText(text) 
        });
    }      
    
    while (pos < max) {  
      
      switch first(["${", "$", "{", "<"], text) {
        case Success("<"):
          if (allowHere('!--')) 
            upto('-->', true);            
          else if (allowHere('!'))
            die('Invalid comment or unsupported processing instruction');
          else if (allowHere('/')) {
            var found = 
              if (allowHere('>')) 
                source[pos - 1 ... pos - 1];
              else 
                ident(true).sure() + expectHere('>');
            if (found != closing)
              die(
                if (isVoid(found))
                  'invalid closing tag for void element <$found>'
                else
                  'found </$found> but expected </$closing>', 
                found.start...found.end
              );
            return result();
          }
          else if (kwd('for')) {
            ret.push(located(function () {
              return CFor(argExpr().sure() + expect('>'), parseChildren('for'));
            }));
          }
          else if (kwd('switch')) 
            ret.push(parseSwitch());
          else if (kwd('if')) 
            ret.push(parseIf());
          else if (kwd('else')) 
            throw new Else(result(), false);
          else if (kwd('elseif')) 
            throw new Else(result(), true);
          else if (kwd('case')) 
            throw new Case(result());
          else 
            ret.push(parseChild());        
          
        case Success("$"):
          
          expr(simpleIdent());
          
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
                
            var p = new Parser(name, content, 0, config);
            for (c in p.parseChildren().value)
              ret.push(c);
            
          }
          else if (allow('...')) {
            var e = ballancedExpr('{', '}');
            ret.push({
              pos: e.pos,
              value: CSplat(e),
            });    
          }
          else
            expr(ballancedExpr('{', '}'));
            
        case Failure(e):
          this.skipIgnored();
          if (closing == null) {
            if (pos < max)//TODO: without this check, the whole source is added
              text(source[pos...max]);
            break;
          }
          else {
            if (this.pos < this.max)
              e.pos.error(e.message);
          }
      }
            
    }
    
    if (closing != null)
      die('unclosed <$closing>');
    
    return result();
  };
  
  function parseSwitch() return located(function () return {
    var target = 
      (switch [argExpr(), config.defaultSwitchTarget] {
        case [Success(v), _]: v;
        case [Failure(v), null]: macro @:pos(makePos(pos)) __data__;
        case [_, v]: v;
      }) + expect('>') + expect('<case');
    
    var cases = [];
    var ret = CSwitch(target, cases);
    var last = false;
    while (!last) {
      var arg = argExpr().sure();
      cases.push({
        values: [arg],
        guard: (if (allow('if')) argExpr().sure() else null) + expect('>'),
        children:
          try {
            last = true;
            parseChildren('switch');
          }
          catch (e:Case) {
            last = false;
            e.children;
          }
      });
    }
    return ret;
  });

  function located<T>(f:Void->T):Located<T> {
    //TODO: this is not unlike super.read
    var start = pos;
    var ret = f();
    return {
      value: ret,
      pos: makePos(start, pos)
    }
  }

  function onlyChild(c:Child):Children
    return { pos: c.pos, value: [c] };
  
  function parseIf():Child {
    var start = pos;
    var cond = argExpr().sure() + expect('>');
    
    function make(cons, ?alt):Child {
      
      return {
        pos: makePos(start, pos),
        value: CIf(cond, cons, alt)
      }
    }
    return 
      try {
        make(parseChildren('if'));
      }
      catch (e:Else) {
        if (e.elseif || switch ident() { case Success(v): if (v == 'if') true else die('unexpected $v', v.start...v.end); default: false; } ) 
          make(e.children, onlyChild(parseIf()));
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
  
  static public function parseRoot(e:Expr, ?config:ParserConfig) {
    if (config == null) 
      config = {
        defaultExtension: 'hxx',
        noControlStructures: false,
      }
    var s = e.getString().sure();
    var pos = Context.getPosInfos(e.pos);
    var p = new Parser(pos.file, s, pos.min + 1, config);
    p.skipIgnored();
    return try {
      p.parseChildren();
    }
    catch (e:Case) 
      p.die('case outside of switch', p.pos - 4 ... p.pos)
    catch (e:Else)
      p.die('else without if', p.pos - 4 ... p.pos); 
  }

}
private class Branch {
  
  public var children(default, null):Children;
  
  public function new(children)
    this.children = children;
    
  public function toString() 
    return 'misplaced ${Type.getClassName(Type.getClass(this))}';
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
