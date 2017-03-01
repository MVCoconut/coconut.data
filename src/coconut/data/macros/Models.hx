package coconut.data.macros;

#if macro
import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;
using haxe.macro.Tools;
using tink.MacroApi;
#end

class Models {
  #if macro 

  static public function build() 
    return ClassBuilder.run([function (c) new ModelBuilder(c)]);

  static function considerValid(pack:Array<String>, name:String) 
    return
      switch pack.concat([name]).join('.') {
        case  'Date' | 'Int' | 'String' | 'Bool' | 'Float': true;
        case 'tink.pure.List': true;
        default: 
          switch [pack, name] {
            case [['tink', 'core'], 'NamedWith' | 'Pair' | 'Lazy' | 'TypedError' | 'Future' | 'Promise']: true;
            default: false;
          };
      }
  
  static public function check(t:Type):Array<String>
    return 
      switch t.reduce() {
        case TAnonymous(_.get().fields => fields):
          var ret = [];
          for (f in fields)
            switch f.kind {
              case FVar(_, AccNever) | FMethod(_):
                for (s in check(f.type))
                  ret.push(s);
              default:
                ret.push('Field ${f.name} of ${t.toString()} needs to have write access `never`');
            }   

          ret;  
        case TFun(_, _): [];   
        case TAbstract(_.get() => a, _) if (!a.meta.has(':coreType') && check(a.type).length == 0): []; 
        case TAbstract(_.get().meta.has(':enum') => true, _): [];
        case TInst(_.get().kind => KTypeParameter(_), _): [];
        case TInst(_, params) | TAbstract(_, params) 
          if (Context.unify(t, Context.getType('tink.state.Observable.ObservableObject')) || Context.unify(t, Context.getType('coconut.data.Model'))):
            [for (p in params) for (s in check(p)) s]; 
        case TAbstract(_.get().meta => m, params)
           | TEnum(_.get().meta => m, params)
           | TInst(_.get().meta => m, params) if (m.has(':pure') || m.has(':observable')):

          [for (p in params) for (s in check(p)) s]; 
        case TEnum(_.get() => e, params):
          var ret = [];
          for (c in e.constructs) 
            switch c.type.reduce() {
              case TFun(args, _):
                for (a in args)
                  for (s in check(a.t)) 
                    ret.push('Enum ${e.name} is not acceptable coconut data because $s for argument ${c.name}.${a.name}');
              default:
            }

          if (ret.length == null)
            e.meta.add(':observable', [], e.pos);
          
          for (p in params) for (s in check(p)) ret.push(s);

          ret;
        case TAbstract(_.get() => { pack: pack, name: name }, params) 
           | TInst(_.get() => { pack: pack, name: name }, params) 
             if (considerValid(pack, name)):
          [for (p in params) for (s in check(p)) s];
        case TDynamic(null): [];
        case v:
          [t.toString() + ' is not acceptable coconut data'];
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
