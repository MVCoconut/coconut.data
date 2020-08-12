package coconut.data.macros;

#if macro
import haxe.macro.Context.*;
using tink.MacroApi;
using tink.CoreApi;
#end

class Helper {
  static public macro function untracked(e) {
    var t = typeExpr(macro @:pos(e.pos) tink.state.Observable.untracked(function () return $e));

    return storeTypedExpr(
      if (t.hasThis()) t;
      else t.extract(t -> switch t.expr {
        case TReturn(t): Some(t);
        default: None;
      }).force()
    );
  }
}