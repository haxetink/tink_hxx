package tink.hxx;

import tink.hxx.Node;
import haxe.macro.Expr;
using StringTools;
using tink.MacroApi;

class Helpers {
  static public function groupDotPaths(attributes:Array<Attribute>) {
    var hasDot = false;

    for (a in attributes)
      switch a {
        case Empty(s) | Regular(s, _):
          if (s.value.indexOf('.') != -1) {
            hasDot = true;
            break;
          }
        default:
      }

    return
      if (!hasDot) attributes;
      else {

        var ret = [],
            objects = new Map<String, Array<ObjectField>>();

        function add(path:StringAt, value:Expr) {

          var parts = path.value.split('.');
          var root = parts[0];

          if (!objects.exists(root)) {
            var fields = [];
            objects[root] = fields;
            ret.push(Attribute.Regular({ pos: path.pos, value: root }, EObjectDecl(fields).at(path.pos)));
          }

          var last = parts.pop(),
              prefix = '';

          for (p in parts) {

            var parent = prefix;

            prefix = switch prefix {
              case '': p;
              case v: '$v.$p';
            }

            if (!objects.exists(prefix)) {
              objects[prefix] = [];

              if (parent != '')
                objects[parent].push({ field: p, expr: EObjectDecl(objects[prefix]).at(path.pos) });
            }
          }

          objects[prefix].push({ field: last, expr: value });
        }

        for (a in attributes)
          switch a {
            case Empty(s) if (s.value.indexOf('.') != -1):
              add(s, macro true);
            case Regular(s, e) if (s.value.indexOf('.') != -1):
              add(s, e);
            default:
              ret.push(a);
          }
        ret;
      }
  }

  static public function normalize(children:Array<Child>)
    return switch children {
      case null: [];
      default:
        [for (c in children) switch c.value {
          case CText(s):
            switch trimString(s.value) {
              case '': continue;
              case v: { value: CText({ pos: s.pos, value: v }), pos: c.pos };
            }
          default: c;
        }];
    }

  static public function trimString(s:String) {

    var pos = 0,
        max = s.length,
        leftNewline = false,
        rightNewline = false;

    while (pos < max) {
      switch s.charCodeAt(pos) {
        case '\n'.code | '\r'.code: leftNewline = true;
        case v:
          if (v > 32) break;
      }
      pos++;
    }

    while (max > pos) {
      switch s.charCodeAt(max-1) {
        case '\n'.code | '\r'.code: rightNewline = true;
        case v:
          if (v > 32) break;
      }
      max--;
    }

    if (!leftNewline)
      pos = 0;
    if (!rightNewline)
      max = s.length;

    return s.substring(pos, max);
  }
}