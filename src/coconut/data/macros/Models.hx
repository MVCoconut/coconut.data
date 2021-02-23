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
    return ModelBuilder.build();

  static function getInitialArgs()
    return
      switch Context.getLocalType() {
        case TInst(_, [TInst(_.get() => cl, params)]):

          switch cl.constructor.get().type.applyTypeParameters(cl.params, params) {
            case TFun([arg], _): arg.t;
            default: throw 'assert';
          }

        default: throw 'assert';
      }


  static function getObservables()
    return
      switch Context.getLocalType() {
        case TInst(_, [_.toComplex() => ct]):

          (macro (null : $ct).observables).typeof().sure();

        default: throw 'assert';
      }

  static function getPatch()
    return
      switch Context.getLocalType() {
        case TInst(_.get() => cl, [_.toComplex() => ct]):

          if (cl.isInterface)
            Context.currentPos().error('Cannot use Patch<T> on interfaces');

          (macro {
            var p = null;
            @:privateAccess (null : $ct).__cocoupdate(p);
            function get<T>(p:tink.core.Promise<T>):T throw 'abstract';
            get(p);
          }).typeof().sure();

        default: throw 'assert';
      }

  static function considerValid(t:BaseType)
    return
      switch t.pack.concat([t.name]).join('.') {
        case  'Date' | 'Int' | 'String' | 'Bool' | 'Float' | 'Null': true;
        case 'tink.pure.List': true;
        case 'tink.Url': true;
        default:
          switch [t.pack, t.name] {
            case [['tink', 'core'], 'NamedWith' | 'Pair' | 'Lazy' | 'TypedError' | 'Future' | 'Promise' | 'Signal' | 'SignalTrigger' | 'Callback']: true;
            default: false;
          };
      }

  static public inline var OBSERVABLE = ':observable';
  static public inline var SKIP_CHECK = ':skipCheck';

  static function checkParams(b:BaseType, params:Array<Type>)
    return [for (i => p in params) if (b.params[i].t.match(TInst(_.get().meta.has(':skipCheck') => false, _)))for (s in check(p)) s];

  static var registered = false;
  static var delayedFieldChecks = new Map<String, Map<String, Bool>>();

  static public function classId(cl:ClassType)
    return cl.module + '.' + cl.name;

  static var deferredChecks = [];

  static public function afterChecking(fn:Void->Void) {
    deferredChecks.push(fn);
    scheduleChecks();
  }
  static public function checkLater(field:String, ?className:String) {

    var target = switch className {
      case null: classId(Context.getLocalClass().get());
      case v: v;
    }

    var checks = switch delayedFieldChecks[target] {
      case null: delayedFieldChecks[target] = new Map();
      case v: v;
    }

    checks[field] = true;
    scheduleChecks();
  }

  static function scheduleChecks()
    if (!registered) {
      registered = true;
      Context.onGenerate(function (types) {
        registered = false;
        for (t in types)
          switch t {

            case TInst(_.get() => cl, _):
              switch delayedFieldChecks[classId(cl)] {
                case null:
                case checks:
                  for (f in cl.fields.get())
                    if (checks[f.name]) switch check(f.type) {
                      case []:
                      case v: f.pos.error(v[0]);
                    }
              }

            default:
          }

        for (c in deferredChecks) c();
      });
    }

  static function baseType<T:BaseType>(r:Ref<T>):BaseType
    return r.get();

  static public function check(t:Type):Array<String>
    return
      switch t {
        case TAnonymous(_.get().fields => fields):
          var ret = [];
          for (f in fields)
            switch f.kind {
              case FVar(_, AccNever) | FMethod(_):
                for (s in check(f.type))
                  ret.push(s);
              default:
                ret.push('Field `${f.name}` of `${t.toString()}` needs to have write access `never`');
            }

          ret;
        case TFun(_, _): [];
        case TAbstract(_.get().meta.has(':enum') => true, _): [];
        case TInst(_.get().kind => KTypeParameter(_), _): [];
        case TInst(baseType(_) => b, params) | TAbstract(baseType(_) => b, params)
          if (
            Context.unify(t, Context.getType('tink.state.internal.ObservableObject'))
              ||
            Context.unify(t, Context.getType('coconut.data.Model'))
          ):
            checkParams(b, params);
        case TAbstract(baseType(_) => t = { meta: m }, params)
           | TType(baseType(_) => t = { meta: m }, params)
           | TEnum(baseType(_) => t = { meta: m }, params)
           | TInst(baseType(_) => t = { meta: m }, params) if (m.has(':pure') || m.has(OBSERVABLE) || m.has(SKIP_CHECK)):

          checkParams(t, params);
        case TEnum(_.get() => e, params):

          recurse(e.meta, () -> {
            var ret = [];
            for (c in e.constructs)
              switch c.type.reduce() {
                case TFun(args, _):
                  for (a in args)
                    for (s in check(a.t))
                      ret.push('Enum ${e.name} is not observable because $s for argument ${c.name}.${a.name}');
                default:
              }

            if (ret.length > 0)
              e.meta.remove(SKIP_CHECK);

            ret.concat(checkParams(e, params));
          });

        case TAbstract(baseType(_) => t, params)
           | TInst(baseType(_) => t, params)
             if (considerValid(t)):
          checkParams(t, params);
        case TDynamic(null): [];//personally, I'm inclined to disallow this
        case TLazy(_):
          check(t.reduce(true));
        case TType(baseType(_) => b, params)
           | TAbstract(baseType(_) => b, params):
          recurse(
            b.meta,
            check.bind(followOnce(t)) //On @:coreType, following returns the type itself, which will then pass via the above @:skipCheck branch
          )
            .concat(checkParams(b, params)).map(function (s)
              return t.toString() + ' is not observable, because $s'
            );
        case TInst(_.get() => {kind: KExpr(_)}, _): // const type param
          [];
        case t = TInst(_.get() => cls, params):

          recurse(cls.meta, function () {

            var ret = switch cls.superClass {
              case null: [];
              case c: check(TInst(cls.superClass.t, cls.superClass.params));
            }

            for (field in cls.fields.get())
              if (isImmutable(field))
                ret = ret.concat(check(field.type))
              else
                ret.push('${t.toString()} is not observable because the field "${field.name}" is mutable');

            return ret;
          })
            .concat(checkParams(cls, params)).map(function (s)
              return t.toString() + ' is not observable, because $s'
            );
        case v:
          [t.toString() + ' is not observable'];
      }

  static function followOnce(t:Type) //TODO: perhaps move this to tink_macro
    return switch t {
      case TAbstract(_.get() => a, params):
        a.type.applyTypeParameters(a.params, params);
      default: Context.follow(t, true);
    }

  static function recurse(meta:MetaAccess, f:Void->Array<String>) {
    meta.add(SKIP_CHECK, [], (macro null).pos);
    var ret = f();
    if (ret.length > 0)
      meta.remove(SKIP_CHECK);
    return ret;
  }

  static function isImmutable(field:ClassField):Bool {
    return
      field.isFinal || switch field.kind {
        case FVar(_, write): write == AccNever;
        case FMethod(kind): kind != MethDynamic;
      }
  }
  #end
}
