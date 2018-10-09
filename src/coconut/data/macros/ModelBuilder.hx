package coconut.data.macros;

#if !macro
  #error
#end

import haxe.macro.Context;
import haxe.macro.Expr;
using tink.MacroApi;
using tink.CoreApi;
using Lambda;

@:enum abstract Kind(String) from String to String {
  var KObservable = ':observable';
  var KConstant = ':constant';
  var KEditable = ':editable';
  var KExternal = ':external';
  var KShared = ':shared';
  var KComputed = ':computed';
  var KLoaded = ':loaded';
}

class ModelBuilder {

  var c:ClassBuilder;
  var isInterface:Bool;

  var argFields:Array<Field> = [];
  var argsOptional:Bool = true;
  var patchFields:Array<Field> = [];
  var observableFields:Array<Field> = [];
  var observableInit:Array<ObjectField> = [];
  var init:Array<{ name:String, expr: Expr }> = [];

  var patchType:ComplexType;

  static var OPTIONAL = [{ name: ':optional', pos: (macro null).pos, params: [] }];
  static var NOMETA = OPTIONAL.slice(OPTIONAL.length);
  static inline var TRANSITION = ':transition';

  public function new(c, ctor) {
    //TODO: put `observables` into a class if `!isInterface`
    this.c = c;
    this.isInterface = c.target.isInterface;

    for (f in c)
      if (!f.isStatic)
        switch f.kind {
          case FProp('get', 'set' | 'never', _, _): 
            switch f.extractMeta(':isVar') {
              case Success(m): m.pos.error('Cannot use `@:isVar` on custom properties in models.');
              default:
            }
          case FProp(_, _, _, _): 
            f.pos.error('Custom properties may only use `get`, `set` and `never` access.');
          case FVar(t, e) if (!f.meta.exists(function (m) return m.name == ':signal')):
            addField(f, t, e);
          default:
        }

    this.patchType = TAnonymous(patchFields);

    for (f in c)
      if (!f.isStatic)
        switch f.kind {
          case FFun(func):
            addMethod(f, func);
          default:
        }      

    addBoilerPlate();

    if (!isInterface) 
      buildConstructor(ctor);
  }

  function buildConstructor(original:Option<Function>) {

    var f:Function = {
      args: [],
      ret: macro : Void,
      expr: macro {},
    };

    var init = null,
        afterInit = [],
        argType = TAnonymous(argFields);

    switch original {
      case None:
      case Some(ctor):
        var exprs = switch ctor.expr {
          case { expr: EBlock(v) }: v;
          case v: [v];
        }

        var beforeInit = [];

        for (e in exprs)
          switch e {
            case macro this = $e: 
              if (init != null) 
                e.reject('can only have one `this = ...` initialization.');
              else
                init = e;
            default:
              if (init == null) beforeInit.push(e);
              else afterInit.push(e);
          }

        if (init == null)
          if (ctor.args.length == 0 || argFields.length == 0) 
            afterInit = beforeInit;
          else
            ctor.expr.reject('Constructor with custom arguments must have `this = ...` clause');
        else {
          c.addMember({
            name: "__coco__computeInitialValues",
            pos: c.target.pos,
            meta: [{ name: ':extern', params: [], pos: c.target.pos}],
            access: [AStatic, AInline],
            kind: FFun({
              args: ctor.args,
              params: ctor.params,//TODO: this also needs the class params
              ret: argType,
              expr: beforeInit.concat([macro return $init]).toBlock()
            })
          });

          var args = [for (a in ctor.args) macro $i{a.name}];

          init = macro var init = __coco__computeInitialValues($a{args});
          f.args = ctor.args;
        }
    }

    if (init == null)
      if (argFields.length > 0)
        f.args.push({
          name: 'init',
          type: argType,
          opt: argsOptional
        });  

    var constr = c.getConstructor(f);
    
    if (init != null)
      constr.addStatement(init);
    else
      if (argsOptional && argFields.length > 0)
        constr.addStatement(macro if (init == null) init = {});

    constr.publish();


    if (!isInterface && !c.target.meta.has(':tink'))
      c.target.meta.add(':tink', [], c.target.pos);
    
    {
      var transform = tink.SyntaxHub.exprLevel.appliedTo(c).force();
      for (f in this.init)
        constr.init(f.name, f.expr.pos, Value(transform(f.expr)), { bypass: true });
    }
    constr.init('__coco_transitionCount', c.target.pos, Value(macro new tink.state.State(0)), {bypass: true});
    constr.init('errorTrigger', c.target.pos, Value(macro tink.core.Signal.trigger()), {bypass: true});
    constr.init('transitionErrors', c.target.pos, Value(macro errorTrigger), {bypass: true});
    
    {
      var observables = TAnonymous(observableFields);
      constr.init('observables', c.target.pos, Value(macro (${EObjectDecl(observableInit).at()} : $observables)), { bypass: true });
    }

    for (s in afterInit)
      constr.addStatement(s);
  }

  function addBoilerPlate() {
    
    var updates = [];
    
    for (f in patchFields) {
      var name = f.name;
      updates.push(macro if (delta.$name != null) $i{stateOf(name)}.set(delta.$name));
    }

    var sparse = TAnonymous([for (f in patchFields) {//this is a workaround for Haxe issue #6316 and also enables settings fields to null
      meta: OPTIONAL,
      name: f.name,
      pos: f.pos,
      kind: FVar(
        switch f.kind { 
          case FProp(_, _, t, _): macro : tink.core.Ref<$t>; 
          default: throw 'assert'; 
        }
      ),
    }]);

    observableFields.push({
      name: 'isInTransition',
      pos: c.target.pos,
      kind: FProp('default', 'never', macro : tink.state.Observable<Bool>),
    });
    observableInit.push({
      field: 'isInTransition',
      expr: macro __coco_transitionCount.observe().map(function (count) return count > 0)
    });
    var observables = TAnonymous(observableFields);

    c.addMembers(macro class {
      @:noCompletion function __cocoupdate(ret:tink.core.Promise<$patchType>) {
        var sync = true;
        var done = false;
        ret.handle(function (o) {
          done = true;
          if(!sync) __coco_transitionCount.set(__coco_transitionCount.value - 1);
          switch o {
            case Success(delta): 
              var sparse = new haxe.DynamicAccess<tink.core.Ref<Any>>(),
                  delta:haxe.DynamicAccess<Any> = cast delta;

              for (k in delta.keys())
                sparse[k] = tink.core.Ref.to(delta[k]);
              var delta:$sparse = cast sparse; 
              $b{updates};
            case Failure(e): errorTrigger.trigger(e);
          }
        });
        if(!done) sync = false;
        if(!sync) __coco_transitionCount.set(__coco_transitionCount.value + 1);
        return ret;
      }
      public var observables(default, never):$observables;
      public var transitionErrors(default, never):tink.core.Signal<tink.core.Error>;
      var errorTrigger(default, never):tink.core.Signal.SignalTrigger<tink.core.Error>;
      var __coco_transitionCount(default, never):tink.state.State<Int>;
      public var isInTransition(get, never):Bool;
      inline function get_isInTransition() return __coco_transitionCount.value > 0;
    });    
  }

  static function stateOf(name:String)
    return '__coco_$name';

  static var ALLOWED = [
    ':noCompletion' => true
  ];

  function addMethod(f:Member, func:Function)
    switch [for (m in f.meta) if (!ALLOWED[m.name]) m] {
      case []:

      case [{ name: TRANSITION, params: params, pos: pos }]:

        if (patchFields.length == 0)
          pos.error('Cannot have transitions when there are no @:observable fields');

        f.publish();
        
        var ret = macro (Noise: tink.core.Noise);

        for (p in params)
          switch p {
            case macro return $e: ret = e;
            case macro synchronize: p.reject('synchronization not yet implemented');
            case macro synchronize = $_: p.reject('synchronization not yet implemented');
            default: p.reject('This expression is not allowed here');
          }          

        var body = switch func.expr {
          case null: pos.error('function body required');
          case e: e.transform(function (e) return switch e {
            case macro @patch $v: macro @:pos(v.pos) ($v : $patchType);
            default: e;
          });
        }

        func.expr = macro @:pos(func.expr.pos) 
          return 
            __cocoupdate((function ():tink.core.Promise<$patchType> $body)())
            .next(function (_) return $ret);

        func.ret = {
          var blank = func.expr.pos.makeBlankType();
          macro : tink.core.Promise<$blank>;
        }

      case v:
        switch f.metaNamed(TRANSITION) {
          case [] | [_]:
          case v: v[1].pos.error('Can only have one @$TRANSITION per function');
        }

        for (m in v)
          if (m.name.charAt(0) == ':' && !allowedOnFunctions[m.name])
            m.pos.error('Tag ${m.name} not allowed');//This is perhaps not the best choice
    }

  static var allowedOnFields = [for (m in [':forward']) m => true];
  static var allowedOnFunctions = [for (m in [TRANSITION, ':keep', ':extern', ':deprecated']) m => true];

  function addField(f:Member, t:ComplexType, e:Expr) {
    if (t == null) 
      f.pos.error('Field requires explicit type');

    if (isInterface && e != null)
      e.reject('expression not allowed here in interfaces');

    var info = fieldInfo(f);

    if (!info.skipCheck)
      switch Models.check(f.pos.getOutcome(t.toType())) {
        case []:
        case v: f.pos.error(v[0]);
      }

    var name = f.name,
        kind = info.kind;

    var injected = kind == KExternal || kind == KShared;
    var settable = kind == KEditable || kind == KShared;
    var mutable = kind == KObservable || kind == KEditable;
    
    var config = {
      comparator: macro null,
      guard: macro null
    }

    for (e in info.params)
      switch e {
        case macro $option = $v:

          function make(ret)
            return macro @:pos(v.pos) function (next:$ret, prev:$ret):$ret return $v;

          switch option.getIdent().sure() {
            case 'guard': 
              config.guard = make(t);
            case 'comparator': 
              config.comparator = make(macro : Bool);
            default: 
              option.reject('only `guard` and `comparator` allowed here');
          }

          if (!mutable)
            option.reject('not supported for `@:$kind` yet');
        default:
          e.reject("only expressions as <option> = <value> allowed here");
      }

    f.publish();
    f.kind = FProp(
      'get',
      if (settable) 'set' else 'never',
      if (kind == KLoaded) macro : tink.state.Promised<$t> else t
    );

    function mk(t:ComplexType, ?optional:Bool):Field
      return {
        name: f.name,
        pos: f.pos,
        meta: if (optional) OPTIONAL else NOMETA,
        kind: FProp('default', 'never', t)
      };

    function addArg(?dFault:Expr) {
      var optional = dFault != null,
          type = switch kind {
            case KExternal: macro : coconut.data.Value<$t>;
            case KShared: macro : coconut.data.Variable<$t>;
            default: t;
          }
      
      argFields.push(mk(type, optional));
      
      if (!optional) argsOptional = false;

      return 
        if (optional) 
          macro @:pos(f.pos) switch init.$name {
            case null: ($dFault : $type);
            case v: v;
          }
        else macro @:pos(f.pos) init.$name;
    }

    var valueType = if (kind == KLoaded) macro : tink.state.Promised<$t> else t,
        state = stateOf(f.name);

    if (f.isPublic) {
      observableFields.push({
        var exposed = if (settable) 'State' else 'Observable';
        mk(macro : tink.state.$exposed<$valueType>);
      });

      observableInit.push({
        field: f.name,
        expr: switch kind {
          case KConstant:
            macro @:pos(f.pos) tink.state.Observable.const($i{name});
          default: 
            macro @:pos(f.pos) $i{state}
        }
      });
    }
    
    {
      var getter = 'get_$name',
          get = switch kind {
            case KConstant: 
              macro @:pos(f.pos) $i{name};
            default: 
              var type =
                if (mutable || settable) macro : tink.state.State<$valueType>;
                else macro : tink.state.Observable<$valueType>;

              c.addMembers(macro class {
                @:noCompletion var $state:$type;
              });

              macro @:pos(f.pos) $i{stateOf(name)}.value;
          };

      c.addMembers(macro class {
        @:noCompletion inline function $getter():$valueType return $get;
      });
    }

    if (settable) {
      var setter = 'set_$name';
      c.addMembers(macro class {
        @:noCompletion function $setter(param:$valueType):$valueType {
          $i{state}.set(param);
          return param;
        }
      });
    }

    if (kind == KObservable)
      patchFields.push(mk(valueType, true));

    init.push(
      if (kind == KConstant) { 
        name: name, 
        expr: switch e {
          case null: addArg();
          case macro @byDefault $v: addArg(v);
          default: e;
        } 
      }
      else {
        name: state,
        expr: switch kind {
          case KComputed | KLoaded:
            switch e {
              case null: 
                f.pos.error('`@$kind` must be initialized with an expression');
              case macro @byDefault $v: 
                e.reject('`@byDefault` not allowed for `@$kind`');
              default: 
            }

            var name = null;
            e = e.transform(function (e) return switch e.expr {
              case EConst(CIdent("$last")): 
                name = MacroApi.tempName(); 
                macro @:pos(e.pos) $i{name};
              default: e;
            });
            
            var impl = 
              if (name != null) macro function ($name:tink.core.Option<$t>) return $e; 
              else macro function () return $e;
            macro @:pos(e.pos) tink.state.Observable.auto($impl);
          default:

            var init = 
              switch e {
                case null: addArg();
                case macro @byDefault $v: addArg(v);
                default: 
                  if (injected) 
                    e.reject('`@:$kind` fields cannot be initialized. Did you mean to use `@byDefault`?');
                  else e;
              }

            if (injected) init;
            else macro @:pos(init.pos) new tink.state.State<$valueType>($init, ${config.comparator}, ${config.guard});
        }
      }
    );
  }

  static var EMPTY = [];

  function fieldInfo(f:Field) {

    var kind:Kind = null,
        skipCheck = false,
        params = EMPTY;

    for (m in f.meta) {

      switch m.name {
        case ':skipCheck': 
        
          if (skipCheck)
            m.pos.error('duplicate @:skipCheck');
          else 
            skipCheck = true;

        case k = KObservable | KConstant | KEditable | KExternal | KShared | KComputed | KLoaded:

          if (isInterface && k != KLoaded)
            m.pos.error('Directives other than `@:$KLoaded` not allowed on interface fields');
          if (kind != null)
            m.pos.error('`@${m.name}` conflicts with previously found `@$kind`');

          params = m.params;
          kind = k;

        case v: 
          if (!allowedOnFields[v])
            m.pos.error('unrecognized @$v');
      }
    }

    if (kind == null)
      kind = KConstant;

    return {
      kind: kind,
      skipCheck: skipCheck,
      params: params,
    }    
  }

  static public function build() {
    var fields = Context.getBuildFields();

    var ctor = {
      var res = None;
      for (f in fields)
        switch f {
          case { name: 'new', kind: FFun(impl) }:
            res = Some(impl);
            if (impl.expr == null)
              f.pos.error('Constructor body required');
            fields.remove(f);
            break;
          default:
        }
      res;
    }

    var builder = new ClassBuilder(fields);

    new ModelBuilder(builder, ctor);

    return builder.export();
  }
}
