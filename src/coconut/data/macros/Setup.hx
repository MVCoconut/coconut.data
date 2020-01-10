package coconut.data.macros;
#if macro
using tink.MacroApi;

class Setup {
  static function run() {
    #if tink_hxx
    tink.hxx.Helpers.setCustomTransformer('coconut.data.Value', {
      reduceType: function (t) return switch t {
        case TAbstract(_, [t]): t;
        default: t;
      },
      postprocessor: PTyped(function (t:haxe.macro.Type, e) {
        return Value.fromExpr.bind(e, switch t {
          case TAbstract(_, [t]): t;
          default: throw 'assert';
        }).bounce();
      })
    });
    #end
  }
}
#end
