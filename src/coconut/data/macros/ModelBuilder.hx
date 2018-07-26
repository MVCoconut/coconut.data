package coconut.data.macros;

#if !macro
  #error
#end

import haxe.macro.Context;
import haxe.macro.Expr;
using tink.MacroApi;
using tink.CoreApi;

@:enum abstract Kind(String) from String to String {
  var KObservable = ':observable';
  var KConstant = ':constant';
  var KEditable = ':editable';
  var KExternal = ':external';
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
  var init:Array<Expr> = [];

  var patchType:ComplexType;

  static var OPTIONAL = [{ name: ':optional', pos: (macro null).pos, params: [] }];
  static var NOMETA = OPTIONAL.slice(OPTIONAL.length);
  static inline var TRANSITION = ':transition';

  public function new(c, ctor:Option<Function>) {
    //TODO: put `observables` into a class if `!isInterface`
    this.c = c;
    this.isInterface = c.target.isInterface;

    for (f in c)
      if (!f.isStatic)
        switch f.kind {
          case FProp(_, _, _, _): 
            f.pos.error('Custom properties not allowed in models');
          case FVar(t, e):
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

    var f:Function = {
      args: [],
      ret: macro : Void,
      expr: macro {},
    };

    if (argFields.length > 0)
      f.args.push({
        name: 'init',
        type: TAnonymous(argFields),
        opt: argsOptional
      });  

    c.getConstructor(f).publish();
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

  function addMethod(f:Member, func:Function)
    switch f.meta {
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

      default:
        switch f.metaNamed(TRANSITION) {
          case [] | [_]:
          case v: v[1].pos.error('Can only have one @$TRANSITION per function');
        }

        for (m in f.meta)
          if (m.name != TRANSITION)
            m.pos.error('Tag ${m.name} not allowed');//This is perhaps not the best choice
    }

  function addField(f:Member, t:ComplexType, e:Expr) {
    if (t == null) 
      f.pos.error('Field requires explicit type');

    if (isInterface && e != null)
      e.reject('expression not allowed here in interfaces');

    var kind = {
      var info = fieldInfo(f);

      if (!info.skipCheck)
        switch Models.check(f.pos.getOutcome(t.toType())) {
          case []:
          case v: f.pos.error(v[0]);
        }

      info.kind;
    }

    f.publish();
    f.kind = FVar(if (kind == KLoaded) macro : tink.state.Promised<$t> else t);

    function mk(t:ComplexType, ?optional:Bool):Field
      return {
        name: f.name,
        pos: f.pos,
        meta: if (optional) OPTIONAL else NOMETA,
        kind: FProp('default', 'never', t)
      };

    function addArg(optional:Bool) {
      argFields.push(
        mk(if (kind == KExternal) macro : coconut.data.Value<$t> else t, optional)
      );
      if (!optional) argsOptional = false;
    }

    observableFields.push(
      mk({
        var value = if (kind == KLoaded) macro : tink.state.Promised<$t> else t;
        macro : tink.state.Observable<$value>;
      })
    );

    var state = stateOf(f.name);

    {
      var type = switch kind {
        case KObservable | KEditable: macro : tink.state.State<$t>;
        default: macro : tink.state.Observable<$t>;
      }

      c.addMembers(macro class {
        @:noCompletion var $state:$type;
      });
    }

    switch kind {
      case KComputed | KLoaded:
        if (e == null) 
          f.pos.error('expression required for @$kind field');
        init.push(macro this.$state = tink.state.Observable.auto(function () return $e));
      default:
        if (kind == KObservable)
          patchFields.push({
            name: f.name,
            pos: f.pos,
            meta: OPTIONAL,
            kind: FProp('default', 'never', t)
          });

        switch e {
          case null:
            addArg(false);
          case macro @byDefault $e:
            addArg(true);
          case v:
        }
    }

  }

  function fieldInfo(f:Field) {

    var kind:Kind = null,
        skipCheck = false;

    for (m in f.meta) {

      function set(k) {
        if (isInterface && k != KLoaded)
          m.pos.error('Directives other than `@:$KLoaded` not allowed on interface fields');
        if (kind != null)
          m.pos.error('`@${m.name}` conflicts with previously found `@$kind`');
        kind = k;
      }

      switch m.name {
        case ':skipCheck': 
          if (skipCheck)
            m.pos.error('duplicate @:skipCheck');
          else 
            skipCheck = true;
        case KObservable: set(KObservable);
        case KConstant: set(KConstant);
        case KEditable: set(KEditable);
        case KExternal: set(KExternal);
        case KComputed: set(KComputed);
        case KLoaded: set(KLoaded);
        case v: m.pos.error('unrecognized @$v');
      }
    }

    if (kind == null)
      kind = KConstant;

    return {
      kind: kind,
      skipCheck: skipCheck
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