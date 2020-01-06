package tink.hxx;

#if macro
import haxe.macro.Expr;
import tink.hxx.Node;
import tink.parse.Char.*;
import tink.parse.*;
import haxe.macro.Context;

using StringTools;
using haxe.io.Path;
using tink.MacroApi;
using tink.CoreApi;

typedef ParserConfig = {
  defaultExtension:String,
  treatNested:Children->Expr,
  ?fragment:String,
  ?defaultSwitchTarget:Expr,
  ?noControlStructures:Bool,
  ?isVoid:StringAt->Bool,
  //?interceptTag:String->Option<StringAt->Expr>, <--- consider adding this back
}

private typedef ParserSourceData = {
  var source:StringSlice;
  var offset:Int;
  var fileName:String;
}

@:forward
abstract ParserSource(ParserSourceData) from ParserSourceData to ParserSourceData {

  @:from static function fromExpr(e:Expr) {
    return ofExpr(e);
  }

  static public function ofExpr(e:Expr):ParserSource {

    var offset = 1;
    switch e {
      case macro @:markup $v:
        e = v;
        offset = 0;
      default:
    }

    var s = e.getString().sure(),
        pos = Context.getPosInfos(e.pos);

    return ({
      source: s,
      offset: pos.min + offset,
      fileName: pos.file,
    }:ParserSourceData);
  }
}

class Parser extends ParserBase<Position, haxe.macro.Error> {

  var fileName:String;
  var config:ParserConfig;
  var isVoid:StringAt->Bool;
  var createParser:ParserSource->Parser;
  var treatNested:Children->Expr;

  function new(setup:ParserSource, createParser, config:ParserConfig) {

    this.createParser = createParser;
    this.config = config;

    super(setup.source, Reporter.expr(this.fileName = setup.fileName), setup.offset);

    function get<T>(o:{ var isVoid(default, null):T; })
      return o.isVoid;

    this.isVoid = switch get(config) {
      case null: function (_) return false;
      case v: v;
    }

    this.treatNested = config.treatNested;
    #if tink_syntaxhub
      switch tink.SyntaxHub.exprLevel.appliedTo(new ClassBuilder()) {
        case Some(f): processExpr = f;
        case None:
      }
    #end

  }

  function withPos(s:StringSlice, ?transform:Int->String->String):StringAt
    return {
      pos: makePos(s.start, s.end),
      value: switch transform {
        case null: s.toString();
        case v: v(s.start, s);
      },
    }

  dynamic function processExpr(e:Expr)
    return e;

  function reenter(e:Expr)
    return switch e {
      case macro @:markup ${{ expr: EConst(CString(_)) }}:
        treatNested(createParser(e).parseRootNode());
      default: e.map(reenter);
    }

  function parseExpr(source:String, pos) {
    source = ~/\/\*[\s\S]*?\*\//g.replace(source, '');
    if (source.trim().length == 0) return macro @:pos(pos) null;

    return
      reenter(processExpr(
        try Context.parseInlineString(source, pos)
        catch (e:haxe.macro.Error) throw e
        catch (e:Dynamic) pos.error(e)
      ));
  }

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

  function parseAttributes() {

    var ret = new Array<Attribute>(),
        selfClosing = false;

    while (!allow('>')) {
      if (allow('//')) {
        upto('\n');
        continue;
      }

      if (allow('/')) {
        expect('>');
        selfClosing = true;
        break;
      }

      if (allow("${") || allow('{')) {
        if (allow('...')) {
          ret.push(Splat(ballancedExpr('{', '}')));
          continue;
        }
        die('unexpected {');
      }
      var attr = withPos(ident().sure());

      ret.push(
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

    return {
      selfClosing: selfClosing,
      attributes: ret,
    }
  }

  function parseChild() return located(function () {
    var fragment = allowHere('>');
    if (fragment && config.fragment == null)
      die('Fragments not supported');
    var name = withPos(
      if (fragment) source[pos-1...pos-1];
      else tagName()
    );

    var hasChildren = true;
    var attrs = [];

    if (!fragment) {
      var r = parseAttributes();
      hasChildren = !r.selfClosing;
      attrs = r.attributes;
      if (isVoid(name)) {
        if (!r.selfClosing)
          name.pos.warning('Consider using a self-closing <${name.value}/> instead of void syntax for better portability.');
        hasChildren = false;
      }
    }

    return CNode({
      name: if (fragment) { value: config.fragment, pos: name.pos } else name,
      attributes: attrs,
      children: if (hasChildren) parseChildren(name.value) else null
    });
  });

  function parseString() {
    var end =
      if (allow("'")) "'";
      else {
        expect('"');
        '"';
      }
    return withPos(upto(end).sure(), replaceEntities);
  }

  function replaceEntities(offset:Int, value:String)
  {
    if (value.indexOf('&') < 0)
      return value;

    var reEntity = ~/&[a-z0-9]+;/gi,
        result = '',
        index = 0;

    while (reEntity.match(value.substr(index)))
    {
      var left = reEntity.matchedLeft(),
          entity = reEntity.matched(0);

      index += left.length + entity.length;
      result += left + switch html.Entities.all[entity] {
        case null:
          makePos(offset + index - entity.length, offset + index).warning('unknown entity $entity');
          entity;
        case e: e;
      };
    }

    result += value.substr(index);
    //TODO: consider giving warnings for isolated `&`
    return result;
  }

  function tagName()
    return ident(true).sure();

  function parseChildren(?closing:String):Children {
    var ret:Array<Child> = [],
        start = pos;

    function result():Children return {
      pos: makePos(start, pos),
      value: ret,
    }

    function handleElse(elseif:Bool)
      return
        switch closing {
          case 'if': throw new Else(result(), elseif);//TODO: this whole throwing business is probably a bad idea
          case null: die('dangling else', start ... pos);
          case v: die('unclosed $v', start ... pos);
        }

    function toChildren(e:Expr):Children
      return
        if (e == null || e.pos == null) null
        else {
          pos: e.pos,
          value: [{ pos: e.pos, value: CExpr(e) }]
        };

    function expr(e:Expr)
      ret.push({
        pos: e.pos,
        value: switch e.expr {
          case EFor(head, body): CFor(head, toChildren(body));
          case EIf(cond, cons, alt): CIf(cond, toChildren(cons), toChildren(alt));
          case ESwitch(target, cases, dFault):

            var cases = [for (c in cases) {
              guard: c.guard,
              values: c.values,
              children: toChildren(c.expr)
            }];

            if (dFault != null)
              cases.push({
                values: [macro _],
                guard: null,
                children: toChildren(dFault),
              });

            CSwitch(target, cases);
          default: CExpr(e);
        }
      });

    function text(slice) {
      var text = withPos(slice, replaceEntities);
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
            upto('-->', true).sure();
          else if (allowHere('!'))
            die('Invalid comment or unsupported processing instruction');
          else if (allowHere('/')) {
            var found =
              if (allowHere('>'))
                source[pos - 1 ... pos - 1];
              else
                tagName() + expectHere('>');
            if (found != closing)
              die(
                if (isVoid(withPos(found)))
                  '</$found> is illegal because <$found> is a void tag'
                else
                  'found </$found> but expected </$closing>',
                found.start...found.end
              );
            return result();
          }
          else if (kwd('for'))
            ret.push(located(function () {
              return CFor(argExpr().sure() + expect('>'), parseChildren('for'));
            }));
          else if (kwd('let'))
            ret.push(located(function () return switch parseAttributes() {
              case { selfClosing: true}: die('<let> may not be self-closing', pos-2...pos);
              case { attributes: a }: CLet(a, parseChildren('let'));
            }));
          else if (kwd('switch'))
            ret.push(parseSwitch());
          else if (kwd('if'))
            ret.push(parseIf());
          else if (kwd('else'))
            handleElse(false);
          else if (kwd('elseif'))
            handleElse(true);
          else if (kwd('case'))
            switch closing {
              case 'switch': throw new Case(result());
              case null: die('dangling case', start ... pos);
              case v: die('unclosed $v', start ... pos);
            }
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

            var p = createParser({ fileName: name, source: (content:StringSlice), offset: 0 });
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

  static var IDENT_START = "$:_" || UPPER || LOWER
    #if tink_parse_unicode
      || 0xF8...0x2FF || 0xF8...0x2FF || 0x370...0x37D || 0x37F...0x1FFF ||
      0x200C...0x200D || 0x2070...0x218F || 0x2C00...0x2FEF ||
      0x3001...0xD7FF || 0xF900...0xFDCF || 0xFDF0...0xFFFD ||
      0x10000...0xEFFFF
    #end
  ;

  static var IDENT_CONTD = IDENT_START || DIGIT || '-.' || 0xB7 || 0x0300...0x036F || 0x203F...0x2040;

  function ident(here = false)
    return
      if ((here && is(IDENT_START)) || (!here && upNext(IDENT_START)))
        Success(readWhile(IDENT_CONTD));
      else
        Failure(makeError('Identifier expected', makePos(pos)));

  override function doSkipIgnored() {
    doReadWhile(WHITE);
    if (allowHere('<!--')) upto('-->', true).sure();
  }

  public function parseRootNode() {
    skipIgnored();
    return try {
      parseChildren();
    }
    catch (e:Case)
      die('case outside of switch', pos - 4 ... pos)
    catch (e:Else)
      die('else without if', pos - 4 ... pos);
  }

  static public function parseRootWith(e:Expr, createParser:ParserSource->Parser)
    return createParser(e).parseRootNode();

  static public function parseRoot(e:Expr, config:ParserConfig) {
    function create(source:ParserSource):Parser
      return new Parser(source, create, config);
    return parseRootWith(e, create);
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
#end