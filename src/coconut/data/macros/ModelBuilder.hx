package coconut.data.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import coconut.data.macros.Models.*;

using tink.MacroApi;
using tink.CoreApi;
using Lambda;

enum abstract Kind(String) to String {
  var KObservable = ':observable';
  var KConstant = ':constant';
  var KEditable = ':editable';
  var KExternal = ':external';
  var KShared = ':shared';
  var KComputed = ':computed';
  var KLoaded = ':loaded';

  public var injected(get, never):Bool;
    function get_injected()
      return switch (cast this:Kind) {
        case KExternal | KShared: true;
        default: false;
      }

  public var settable(get, never):Bool;
    function get_settable()
      return switch (cast this:Kind) {
        case KEditable | KShared: true;
        default: false;
      }

  public var mutable(get, never):Bool;
    function get_mutable()
      return switch (cast this:Kind) {
        case KObservable | KEditable: true;
        default: false;
      }

  public var virtual(get, never):Bool;
    function get_virtual()
      return switch (cast this:Kind) {
        case KComputed | KLoaded: true;
        default: false;
      }

  public var initEarly(get, never):Bool;
    function get_initEarly()
      return virtual || injected;
}

class ModelBuilder {

  var c:ClassBuilder;
  var className:String;
  var isInterface:Bool;

  var argFields:Array<Field> = [];
  var argsOptional:Bool = true;
  var patchFields:Array<Field> = [];
  var observableFields:Array<Field> = [];
  var observableInit:Array<ObjectField> = [];
  var init:Array<{ name:String, expr: Expr }> = [];

  var patchType:ComplexType;

  static final OPTIONAL = [{ name: ':optional', pos: (macro null).pos, params: [] }];
  static final NOMETA = OPTIONAL.slice(OPTIONAL.length);
  static inline var TRANSITION = ':transition';

  public function new(c, ctor) {
    //TODO: put `observables` into a class if `!isInterface`
    this.c = c;
    this.className = Models.classId(c.target);
    this.isInterface = c.target.isInterface;

    switch c.target.superClass {
      case null:
      case _.t.get() => cl:
        for (i in cl.interfaces)
          if (i.t.toString() == 'coconut.data.Model')
            c.target.pos.error('cannot extend models');
    }

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
          case FVar(t, e) if (!f.meta.exists(function (m) return m.name == ':signal' || m.name == ':untracked')):
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
            pos: (macro null).pos,
            meta: [{ name: ':extern', params: [], pos: (macro null).pos}],
            access: [AStatic, AInline],
            kind: FFun({
              args: ctor.args,
              params: ctor.params,//TODO: this also needs the class params
              ret: argType,
              expr: beforeInit.concat([macro return $init]).toBlock()
            })
          });

          var args = [for (a in ctor.args) macro $i{a.name}];

          init = macro var __coco_init = __coco__computeInitialValues($a{args});
          f.args = ctor.args;
        }
    }

    if (init == null)
      if (argFields.length > 0)
        f.args.push({
          name: '__coco_init',
          type: argType,
          opt: argsOptional
        });

    var constr = c.getConstructor(f);

    if (init != null)
      constr.addStatement(init);
    else
      if (argsOptional && argFields.length > 0)
        constr.addStatement(macro if (__coco_init == null) __coco_init = {});

    constr.publish();

    {
      var transform =
        switch #if tink_syntaxhub tink.SyntaxHub.exprLevel.appliedTo(c) #else None #end {
          case Some(f): f;
          default: e -> e;
        }

      for (f in this.init)
        constr.init(f.name, f.expr.pos, Value(macro @:pos(f.expr.pos) coconut.data.macros.Helper.untracked(${transform(f.expr)})));
    }
    constr.init('__coco_transitionCount', (macro null).pos, Value(macro new tink.state.State(0)));
    constr.init('errorTrigger', (macro null).pos, Value(macro tink.core.Signal.trigger()));
    constr.init('transitionErrors', (macro null).pos, Value(macro errorTrigger));
    constr.init('annex', (macro null).pos, Value(macro new coconut.data.helpers.Annex(this)));
    {
      var observables = TAnonymous(observableFields);
      constr.init('observables', (macro null).pos, Value(macro (${EObjectDecl(observableInit).at()} : $observables)));
    }

    if (afterInit.length > 0)
      constr.addStatement(macro tink.state.Observable.untracked(function () {
        (function () $b{afterInit})();
        return null;
      }));
  }

  function addBoilerPlate() {

    var updates = [];

    for (f in patchFields) {
      var name = f.name;
      updates.push(macro if (existent.$name) $i{stateOf(name)}.set(delta.$name));
    }

    observableFields.push({
      name: 'isInTransition',
      pos: (macro null).pos,
      kind: FProp('default', 'never', macro : tink.state.Observable<Bool>),
    });
    observableInit.push({
      field: 'isInTransition',
      expr: macro __coco_transitionCount.observe().map(function (count) return count > 0)
    });
    var observables = TAnonymous(observableFields);

    var delta = TAnonymous([for (f in patchFields) {
      name: f.name,
      pos: f.pos,
      meta: f.meta,
      kind: switch f.kind {
        case FProp('default', 'never', t = TFunction(_)):
          FProp('default', 'never', macro : coconut.data.Model.FunctionReference<$t>);
        case v: v;
      },
    }]);// workaround for https://github.com/HaxeFoundation/haxe/issues/6316 \o/

    var self = c.target.name.asComplexType([for (p in c.target.params) TPType(p.name.asComplexType())]);
    var fields:Array<Member> = (macro class {
      @:noCompletion function __cocoupdate(ret:tink.core.Promise<$patchType>) {
        var sync = true;
        var done = false;
        ret.handle(function (o) {
          done = true;
          if(!sync) __coco_transitionCount.set(__coco_transitionCount.value - 1);
          switch o {
            case Success(delta):
              var delta:$delta = delta;
              var existent = tink.Anon.existentFields(delta);
              tink.state.Scheduler.atomically(() -> {
                $b{updates};
              }, true);
              this._updatePerformed.trigger(delta);
            case Failure(e): errorTrigger.trigger(e);
          }
        });
        if(!done) sync = false;
        if(!sync) __coco_transitionCount.set(__coco_transitionCount.value + 1);
        return ret;
      }
      var _updatePerformed:tink.core.Signal.SignalTrigger<$patchType> = tink.core.Signal.trigger();
      public var updatePerformed(get, never):tink.core.Signal<$patchType>;
        function get_updatePerformed() return _updatePerformed;
      public final observables:$observables;
      public final transitionErrors:tink.core.Signal<tink.core.Error>;
      @:noCompletion final errorTrigger:tink.core.Signal.SignalTrigger<tink.core.Error>;
      @:noCompletion final __coco_transitionCount:tink.state.State<Int>;
      public var isInTransition(get, never):Bool;
      @:noCompletion inline function get_isInTransition() return __coco_transitionCount.value > 0;
    }).fields;

    for (f in fields)
      if (f.isPublic || !isInterface)
        c.addMember(f);

    if (!isInterface) {
      c.addMembers(macro class {
        public final annex:coconut.data.helpers.Annex<$self>;
        #if tink_state.debug
          static var __id_counter = 0;
          final __coco_id = __id_counter++;
        #end
      });

      if (!c.hasMember('toString'))
        c.addMembers(macro class {
          #if tink_state.debug @:keep #end public function toString():String {
            return $v{c.target.name} #if tink_state.debug + '#' + __coco_id #end;//TODO: consider adding fields
          }
        });
    }
  }

  static function stateOf(name:String)
    return '__coco_$name';

  static var ALLOWED = [
    ':noCompletion' => true
  ];

  function addMethod(f:Member, func:Function) {

    for (m in f.meta)
      if (m.name.charAt(0) == ':' && !allowedOnFunctions[m.name])
        m.pos.error('@${m.name} not allowed in models');//TODO: make suggestions

    switch f.metaNamed(TRANSITION) {
      case []:
      case [{ name: TRANSITION, params: params, pos: pos }]:

        if (isInterface) {
          var ret = switch func.ret {
            case null: macro : tink.core.Noise;
            case v: v;
          }

          if (params.length > 0)
            params[0].reject('@:transition customization not allowed on interfaces');

          func.ret = macro : tink.core.Promise<$ret>;
        }
        else {
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
              .next(function (_) return tink.core.Promise.lift($ret));
        }
      case v: v[1].pos.error('Can only have one @$TRANSITION per function');
    }

  }

  static var allowedOnFields = [for (m in [':forward', ':noCompletion']) m => true];
  static var allowedOnFunctions = [for (m in [TRANSITION, ':keep', ':extern', ':deprecated', ':noCompletion']) m => true];

  function addField(f:Member, t:ComplexType, e:Expr) {
    if (t == null)
      f.pos.error('Field requires explicit type');

    if (isInterface && e != null)
      e.reject('expression not allowed here in interfaces');

    var info = fieldInfo(f);

    if (!info.skipCheck)
      Models.checkLater(f.name, className);

    var name = f.name,
        kind = info.kind;

    var config = {
      comparator: macro null,
      guard: macro null
    }

    for (e in info.params)
      switch e {
        case macro $option = $v:

          switch option.getIdent().sure() {
            case 'guard':
              config.guard = macro @:pos(v.pos) function (param):$t return $v;
            case 'comparator':
              config.comparator = macro @:pos(v.pos) function (next:$t, prev:$t):Bool return $v;
            default:
              option.reject('only `guard` and `comparator` allowed here');
          }

          if (!kind.mutable)
            option.reject('not supported for `@:$kind` yet');
        default:
          e.reject("only expressions as <option> = <value> allowed here");
      }

    f.publish();

    var valueType = if (kind == KLoaded) macro : tink.state.Promised<$t> else t;

    f.kind = FProp(
      'get',
      if (kind.settable) 'set' else 'never',
      valueType
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
          macro @:pos(f.pos) switch __coco_init.$name {
            case null: ($dFault : $type);
            case v: v;
          }
        else macro @:pos(f.pos) __coco_init.$name;
    }

    var state = stateOf(f.name);

    if (f.isPublic) {
      observableFields.push({
        var exposed = if (kind.settable) 'State' else 'Observable';
        mk(macro : tink.state.$exposed<$valueType>);
      });

      observableInit.push({
        field: f.name,
        expr: switch kind {
          case KConstant:
            macro @:pos(f.pos) tink.state.Observable.const(this.$name #if tink_state.debug , () -> this.toString() + '.' + $v{f.name} + '(' + this.$name + ')' #end);
          default:
            macro @:pos(f.pos) $i{state}
        }
      });
    }

    if (!isInterface) {
      var getter = 'get_$name',
          get = switch kind {
            case KConstant:
              f.addMeta(':isVar', (macro null).pos);
              macro @:pos(f.pos) $i{name};
            default:
              var type =
                if (kind.mutable || kind.settable) macro : tink.state.State<$valueType>;
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

    var owned = kind == KObservable || kind == KEditable;

    if (kind.settable && !isInterface) {
      var setter = 'set_$name';
      c.addMembers(macro class {
        @:noCompletion function $setter(param:$valueType):$valueType {
          ${
            if (owned) macro _updatePerformed.trigger({ $name: param })
            else macro {}
          }
          $i{state}.set(param);
          return param;
        }
      });
    }

    if (owned)
      patchFields.push(mk(valueType, true));

    var i =
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
        expr:
          if (kind.virtual)
            if (isInterface) macro null;
            else buildComputed(kind, f, info.params, e, t);
          else {
            var init =
              switch e {
                case null: addArg();
                case macro @byDefault $v: addArg(v);
                default:
                  if (kind.injected)
                    e.reject('`@:$kind` fields cannot be initialized. Did you mean to use `@byDefault`?');
                  else e;
              }

            if (kind.injected) init;
            else macro @:pos(init.pos) new tink.state.State<$valueType>($init, ${config.comparator}, ${config.guard}, null #if tink_state.debug , (id:Int) -> this.toString() + '.' + $v{f.name} + '(' + $i{state}.value + ')' #end);
          }
      }
    if (kind.initEarly) init.unshift(i); else init.push(i);
  }

  static public function buildComputed(kind:Kind, f:Member, metaParams:Array<Expr>, e:Expr, t:ComplexType) {
    switch e {
      case null:
        f.pos.error('`@$kind` must be initialized with an expression');
      case macro @byDefault $v:
        e.reject('`@byDefault` not allowed for `@$kind`');
      default:
    }

    var comparator = macro null;
    for (e in metaParams)
      switch e {
        case macro comparator = $c: comparator = c;
        default: e.reject('only comparator = <expr> allowed here');
      }

    var name = null;
    e = e.transform(function (e) return switch e.expr {
      case EConst(CIdent("$last")):
        if (name == null)
          name = MacroApi.tempName();
        macro @:pos(e.pos) $i{name};
      default: e;
    });

    var ret = if (kind == KLoaded) macro : tink.core.Promise<$t> else t;

    var impl =
      if (name != null) macro @:pos(e.pos) function ($name:tink.core.Option<$t>):$ret return $e;
      else macro @:pos(e.pos) function ():$ret return $e;

    var ret = if (kind == KLoaded) macro : tink.state.Promised<$t> else t;

    return macro @:pos(e.pos) new tink.state.internal.AutoObservable<$ret>($impl, $comparator #if tink_state.debug , (_:Int) -> this.toString() + '.' + $v{f.name} #end);
  }

  static var EMPTY = [];

  function fieldInfo(f:Field) {

    var kind:Kind = null,
        skipCheck = false,
        params = EMPTY;

    for (m in f.meta) {

      switch m.name {
        case SKIP_CHECK:

          if (skipCheck)
            m.pos.error('duplicate @$SKIP_CHECK');
          else
            skipCheck = true;

        case k = KObservable | KConstant | KEditable | KExternal | KShared | KComputed | KLoaded:

          if (isInterface && k != KLoaded && k != KEditable)
            m.pos.error('Directives other than `@:$KLoaded` and `@:$KEditable` not allowed on interface fields');
          if (kind != null)
            m.pos.error('`@${m.name}` conflicts with previously found `@$kind`');

          params = m.params;
          kind = cast k;//TODO: given the above pattern it seems weird to have to cast here

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

  static final processed = new Map();
  static public function build() {

    var target = Context.getLocalClass().get();

    var className = Models.classId(target);

    if (processed[className]) return null;

    processed[className] = true;

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

    var builder = new ClassBuilder(target, fields);

    for (pass in passes)
      ctor = pass(builder, ctor);
    #if hotswap
      hotswap.Macro.lazify(builder);
    #end

    return builder.export(builder.target.meta.has(':explain'));
  }

  static public final passes = {
    var queue = new tink.priority.Queue();
    queue.whenever((builder, ctor) -> {
      new ModelBuilder(builder, ctor);
      ctor;
    });
    queue;
  }
}
#end
