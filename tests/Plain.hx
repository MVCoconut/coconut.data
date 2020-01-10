#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
using tink.MacroApi;
#end

class Plain {
  static public macro function hxx(e:Expr)
    return
      #if tink_hxx
        {
          var ctx = new tink.hxx.Generator().createContext();
          return ctx.generateRoot(
            tink.hxx.Parser.parseRoot(e, {
              defaultExtension: 'hxx',
              noControlStructures: false,
              defaultSwitchTarget: macro __data__,
              isVoid: ctx.isVoid,
              treatNested: function (children) return ctx.generateRoot.bind(children).bounce(),
            })
          );
        }
      #else
        Context.currentPos().error('need to compile with -lib tink_hxx');
      #end
}