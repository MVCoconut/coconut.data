package coconut.data;

import tink.state.Observable;

#if macro
import haxe.macro.Context.*;
using haxe.macro.Tools;
using tink.MacroApi;
#end

@:forward
abstract Value<T>(Observable<T>) from Observable<T> to Observable<T> {
  public inline function or(fallback:Value<T>):Observable<T>
    return if (this == null) fallback else this;

  @:from macro static function lift(e) {
    //TODO: be a bit smarter about detecting constants and also make sure literal `null` is handled properly
    return
      switch typeExpr(e) {
        case { expr: TConst(_) }:
          macro @:pos(e.pos) tink.state.Observable.const($e);
        case { expr: TField(owner, FInstance(_, _, f)) } if (unify(owner.t, getType('coconut.data.Model'))):
          //TODO: a more aggressive optimization would be to look into the getter and if it merely accesses an observable, grab that ... would reduce the cost of spreading attributes into a child in coconut.ui
          var name = f.get().name;
          macro @:pos(e.pos) ${storeTypedExpr(owner)}.observables.$name;
        case { t: type }:
          var expected = switch getExpectedType().reduce() {
            case TAbstract(_.get().module => 'coconut.data.Value', [_.toComplex() => e]): e;
            case v: throw 'assert: $v';
          }
          if (unify(type, getType('tink.state.Observable.ObservableObject'))) {
            var found = typeof(macro @:pos(e.pos) {
              function get<T>(o:tink.state.Observable<T>) return o.value;
              get($e);
            }).toComplex();
            typeof(macro @:pos(e.pos) ((cast null : $found) : $expected));
            macro @:pos(e.pos) ($e : tink.state.Observable<$found>).map(function (x):$expected return x);
          }
          else {
            function mk(e, t)
              return macro @:pos(e.pos) tink.state.Observable.auto(function ():$t return $e);
            switch expected {
              case (macro : tink.state.Observable.Observable<$t>), //TODO: this case is only here for tink_macro <= 0.16.3 versions
                (macro : tink.state.Observable<$t>):
                macro @:pos(e.pos) (${mk(e, t)}:tink.state.Observable<$expected>);
              default:
                mk(e, expected);
            }
          }
      }
  }
}