package coconut.data;

import tink.state.Observable;

#if macro
import haxe.macro.Context.*;
using haxe.macro.Tools;
using tink.MacroApi;
#end

@:forward
abstract Value<T>(Observable<T>) from Observable<T> to Observable<T> {
  public inline function or(constant:T):Observable<T>
    return if (this == null) constant else this;

  @:from macro static function lift(e) {
    //TODO: be a bit smarter about detecting constants and also make sure literal `null` is handled properly
    return
      switch typeExpr(e) {
        case { expr: TConst(_) }:
          macro @:pos(e.pos) tink.state.Observable.const($e);
        case { t: type }:
          if (unify(type, getType('tink.state.Observable.ObservableObject'))) {
            
            var found = typeof(macro @:pos(e.pos) {
              function get<T>(o:tink.state.Observable<T>) return o.value;
              get($e);
            }).toComplex();
            switch getExpectedType().reduce() {
              case TAbstract(_.get().module => 'coconut.data.Value', [_.toComplex() => expected]):
                typeof(macro @:pos(e.pos) ((cast null : $found) : $expected));
                macro @:pos(e.pos) ($e : tink.state.Observable<$found>).map(function (x):$expected return x);
              case v: 
                throw 'assert: $v';
            }
          }
            // e.reject('${type.toString()} should be ${getExpectedType().toString()}')
          else
            macro @:pos(e.pos) tink.state.Observable.auto(function () return $e);
      }
  }
}