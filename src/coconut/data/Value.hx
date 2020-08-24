package coconut.data;

import tink.state.Observable;

#if macro
import haxe.macro.Context.*;
import haxe.macro.Type;
import haxe.macro.Expr;

using haxe.macro.Tools;
using tink.MacroApi;
using tink.CoreApi;
#end

@:forward @:transitive
abstract Value<T>(Observable<T>) from Observable<T> to Observable<T> from ObservableObject<T> from tink.state.State<T> {

  @:to inline function getValue():T
    return this.value;

  public inline function or(fallback:Value<T>):Observable<T>
    return if (this == null) fallback else this;

  #if macro
  static public function getParam(t:Type)
    return switch t {
      case null: typeof(macro @:pos(currentPos()) (cast null));
      case TAbstract(_.get().module => 'coconut.data.Value', [expected]):
        expected;
      case t:
        t;//not sure if doing it for all types is really the best choice
    }

  static public function ofExpr(e:Expr, expected:Type) {
    var expectedCt = expected.toComplex();

    return switch e {
      case macro true, macro false, { expr: EConst(_.match(CIdent(_)) => false) }:
        macro @:pos(e.pos) tink.state.Observable.const(($e : $expectedCt));
      default:

        function unwrap(t:TypedExpr)
          return switch t.expr {
            case TCast(t, _): unwrap(t);
            case TParenthesis(t): unwrap(t);
            case TMeta(_, t): unwrap(t);
            case TBlock([t]): unwrap(t);
            case TReturn(t): unwrap(t);
            default: t;
          }

        var te = unwrap(typeExpr(macro @:pos(e.pos) (function ():$expectedCt { return $e; })));
        //TODO: the following TypedExpr patterns seems very brittle ... better add thorough tests

        function undouble(te:TypedExpr)
          return switch te {
            case { expr: TCall({ expr: TField(_, FStatic(_.get().module => 'tink.state.Observable' | 'tink.state.State', _.get().name => 'get_value')) }, [value]) }:
              Some(value);
            default: None;
          }

        switch te.expr {
          case TFunction(undouble(_.expr) => Some(e)):
            storeTypedExpr(e);
          //TODO: add case to optimize attribute and model access
          default:
            macro @:pos(e.pos) tink.state.Observable.auto(${storeTypedExpr(te)});
        }
    }
  }
  #end
  macro static public function fromHxx(e:Expr)
    return ofExpr(e, getParam(getExpectedType()));

  @:from macro static function lift(e) {
    //TODO: be a bit smarter about detecting constants and also make sure literal `null` is handled properly
    return
      switch typeExpr(e) {
        case { expr: TConst(_) }:
          var ct = getParam(getExpectedType().reduce()).toComplex();
          (macro @:pos(e.pos) tink.state.Observable.const(($e:$ct)));
        case { expr: TField(owner, FInstance(_, _, f)) } if (unify(owner.t, getType('coconut.data.Model')) && getLocalMethod() != 'new')://guarding against constructor for https://github.com/MVCoconut/coconut.data/issues/37
          //TODO: a more aggressive optimization would be to look into the getter and if it merely accesses an observable, grab that ... would reduce the cost of spreading attributes into a child in coconut.ui
          var name = f.get().name;
          macro @:pos(e.pos) ${storeTypedExpr(owner)}.observables.$name;
        case te = { t: type }:
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