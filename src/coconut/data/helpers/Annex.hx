package coconut.data.helpers;

import coconut.data.macros.Models;
#if macro
import haxe.macro.Context.*;
import haxe.macro.Type;
import haxe.macro.Expr;
using haxe.macro.Tools;
using tink.MacroApi;
#end

class Annex<Target:Model> {

  var target:Target;
  var registry:Map<Dynamic, Dynamic>;

  public function new(target:Target) {
  	this.target = target;
    this.registry = cast new haxe.ds.ObjectMap();
  }

  @:noCompletion public function __doGet<A>(cls:Class<A>, fn:Target->A):A
    return switch registry[cls] {
      case null: registry[cls] = fn(target);
      case v: v;
    }

  public macro function get(ethis:Expr, cls:Expr) {
    var targetType =
      switch typeof(ethis).reduce() {
        case TInst(_, [t]): t;
        default: throw 'assert';
      }

    var ret = null;
    function getPath(e:Expr) return switch e {
      case macro $i{name}: name;
      case macro ${getPath(_) => p}.$name: '$p.$name';
      case { expr: EDisplay(_) | EDisplayNew(_) }:
        ret = e;
        '';
      default: e.reject('should be a dot-path');
    }

    var cPath = getPath(cls);

    if (ret != null)
      return ret;

    var cType = try getType(cPath) catch (e:Dynamic) cls.pos.error(e);
    var cType = switch cType {
      case TInst(_.get() => c, _):
        if (c.params.length > 0)
          cls.reject('cannot use this class, because it has type parameters');
        if (c.constructor == null)
          cls.reject('class has no constructor');
        if (!c.meta.has(':coconut.check_scheduled')) {
          c.meta.add(':coconut.check_scheduled', [], (macro null).pos);
          var pos = cls.pos;
          Models.afterChecking(function () {
            switch Models.check(cType) {
              case []:
              case v: error(v[0], pos);
            }
          });
        }
        c;
      default:
        cls.reject('not a class');
    }

    inline function matches(t:Type)
      return unify(targetType, t);

    switch cType.constructor.get().type.reduce() {
      case TFun(args, ret):
        for (i in 0...args.length) {

          var a = args[i];

          inline function missing(name:String)
            cls.reject('missing value for mandatory constructor argument $name');

          inline function yield(expr:Expr) {
            for (i in i + 1...args.length)
              switch args[i] {
                case { opt: true }:
                case { name: n }: missing(n);
              }

            var NULL = macro @:pos(cls.pos) cast null;
            var args = [for (i in 0...i) NULL];
            args.push(expr);
            var ct = cPath.asTypePath();
            return macro @:pos(cls.pos) $ethis.__doGet($cls, function (target) return new $ct($a{args}));
          }

          if (matches(a.t))
            return yield(macro target);
          else switch a.t.reduce() {
            case TAnonymous(_.get().fields => fields):
              var hit = null;
              for (f in fields)
                if (matches(f.type)) {
                  hit = f.name;
                  break;
                }

              if (hit != null) {
                for (f in fields)
                  if (f.name != hit && !f.meta.has(':optional'))
                    missing('${a.name}.${f.name}');
                return yield(macro @:pos(cls.pos) { $hit: target });
              }
            default:
          }

          if (!a.opt)
            missing(a.name);
        }

        return cls.reject('${cls.toString()} does not seem to accept ${targetType.toString()}');

      default:
        throw 'assert';
    }
  }
}