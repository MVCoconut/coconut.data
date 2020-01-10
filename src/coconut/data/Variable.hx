package coconut.data;

import tink.state.*;
#if macro
import haxe.macro.Context.*;
import haxe.macro.Type;
import haxe.macro.Expr;
using haxe.macro.Tools;
using tink.MacroApi;
#end

@:forward
abstract Variable<T>(State<T>) from State<T> to State<T> to Observable<T> {
  static public macro function make(e)
    return ofExpr(e);

  public inline function or(fallback:Variable<T>):State<T>
    return if (this == null) fallback else this;

  #if macro
  static public function getParam(t:Type)
    return switch t {
      case null: typeof(macro @:pos(currentPos()) (cast null));
      case TAbstract(_.get().module => 'coconut.data.Variable', [expected]):
        expected;
      case t:
        t;//not sure if doing it for all types is really the best choice
    }

  static function shouldCheck(e:Expr)
    return switch e {
      case { expr: ECheckType(e, _)} | macro ($e): shouldCheck(e);
      case macro @:skipCheck $_: false;
      default: true;
    }

  static public function ofExpr(e:Expr)
    return (switch typeExpr(e) {
      case done = followWithAbstracts(_.t) => TInst(_.get() => { module: 'tink.state.State', name: 'StateObject' }, _):
        storeTypedExpr(done);
      case { t: t }:
        switch e {
          case macro ${typeExpr(_) => v}.$name: // TODO: consider checking if the target is valid

            var ret = storeTypedExpr(v);

            if (shouldCheck(e)) {
              var ownerT = v.t,
                  pos = e.pos;

              coconut.data.macros.Models.afterChecking(function () {
                switch coconut.data.macros.Models.check(ownerT) {
                  case []:
                  case v:
                    pos.error('Target not observable: ${v[0]}');
                }
              });
            }

            typeof(macro @:pos(e.pos) $ret.$name = cast null);

            macro @:pos(e.pos) {
              var target = tink.state.Observable.auto(function () return $ret);
              @:pos(e.pos) tink.state.State.compound(
                tink.state.Observable.auto(function () return target.value.$name), // consider using .map here
                function (value) target.value.$name = value
              );
            }

        default:
          e.reject('expression should be a field or of type State (found ${t.toString()})');
      }
    });
  #end
}