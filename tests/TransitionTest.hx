package ;
@:asserts
class TransitionTest {
  public function new() {}

  public function normal() {
    var model = new TransitionModel();

    asserts.assert(!model.isInTransition);
    var transition = model.modify(1);
    asserts.assert(model.isInTransition);
    transition.handle(function(_) {
      asserts.assert(model.value == 1);
      asserts.assert(!model.isInTransition);
      asserts.done();
    });

    return asserts;
  }

  public function error() {
    var model = new TransitionModel();
    var errorEmitted = false;
    model.transitionErrors.handle(function(_) errorEmitted = true);
    return model.failure().map(function(_) return assert(errorEmitted));
  }

  static function init() {//this doesn't really belong here, but oh well ...
    var a:InitialArgs<TransitionModel> = {};
    a = { value: 12 };
    a = {};
  }
}

@:tink class TransitionModel implements Model {
  @:observable var value:Int = @byDefault 0;
  #if tink_lang
  @:signal var boink:String;
  #end
  @:transition
  function modify(v:Int) {
    #if tink_lang
    _boink.trigger('blub');
    #end
    return Future.async(function(cb) haxe.Timer.delay(cb.bind({value: v}), 10));
  }

  @:transition
  function failure()
    return new Error('Dummy');
}