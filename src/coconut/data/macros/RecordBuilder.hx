package coconut.data.macros;

#if !macro
  #error
#end

import haxe.macro.Context;
import haxe.macro.Expr;
import tink.macro.BuildCache;
using tink.MacroApi;
using tink.CoreApi;

class RecordBuilder {
  static function build() {
    return BuildCache.getType('coconut.data.Record', function (ctx:BuildContext) {
      var name = ctx.name;
      
      var ret = macro class $name implements coconut.data.Model {
        @:transition function update(o)
          return tink.core.Promise.lift(o);
      }

      function cls(td:TypeDefinition)
        for (f in td.fields) ret.fields.push(f);

      for (f in ctx.type.getFields().sure())
        if (f.isPublic) { 
          var name = f.name,
              t = f.type.toComplex();
          
          cls(macro class {
            @:observable var $name:$t;
          });
        }

      return ret;
    });
  }
}