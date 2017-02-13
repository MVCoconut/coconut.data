package coconut.data.macros;

#if macro
import haxe.macro.Expr;
using tink.MacroApi;
#end

class Models {
  #if macro 
  static public function build() 
    return ClassBuilder.run([function (c) new ModelBuilder(c)]);

  static public function isAssignment(op:Binop)
    return switch op {
      case OpAssign | OpAssignOp(_): true;
      default: false; 
    }

  static public function buildTransition(e:Expr, ret:Expr) { 
    
    var ret = switch ret {
      case null | macro null: macro ret;
      case v: macro ret.next(function (_) return $v);
    }

    return macro @:pos(e.pos) {
      var ret = $e();
      ret.handle(function (o) switch o {
        case Success(v): __cocoupdate(v);
        case _:
      });
      return $ret;
    }

  }
  #end
  macro static public function transition(e, ?ret) 
    return buildTransition(e, ret);
}
