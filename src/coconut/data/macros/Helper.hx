package coconut.data.macros;

#if macro
import haxe.macro.Type;
import haxe.macro.Context.*;
using haxe.macro.Tools;
using tink.CoreApi;
#end

class Helper {
  #if macro
  static function hasThis(t)
    return find(t, t -> t.expr.match(TConst(TThis) | TLocal({ name: '`this' }))) != None;

  static function find(t, test):Option<TypedExpr>
    return try {
      function rec(t:TypedExpr) switch t {
        case null:
        default:
          if (test(t)) throw Some(t);
          t.iter(rec);
      }
      rec(t);
      None;
    }
    catch (e:Option<Dynamic>) cast e;
  #end
  static public macro function untracked(e) {
    var t = typeExpr(macro @:pos(e.pos) tink.state.Observable.untracked(function () return $e));

    return
      if (hasThis(t)) storeTypedExpr(t);
      else switch find(t, t -> t.expr.match(TReturn(_))) {
        case Some({ expr: TReturn(t) }):
          storeTypedExpr(t);
        default:
          throw 'assert';
      }
  }
}