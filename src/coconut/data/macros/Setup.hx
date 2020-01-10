package coconut.data.macros;
#if macro
using tink.MacroApi;

class Setup {
  static function run() {
    #if tink_hxx
      tink.hxx.Helpers.setCustomTransformer('coconut.data.Value', {
        reduceType: Value.getParam,
        postprocessor: PTyped(function (t, e)
          return Value.ofExpr(e, Value.getParam(t))
        )
      });
      tink.hxx.Helpers.setCustomTransformer('coconut.data.Variable', {
        reduceType: Variable.getParam,
        postprocessor: PTyped(function (t, e) return Variable.ofExpr(e))
      });
    #end
  }
}
#end
