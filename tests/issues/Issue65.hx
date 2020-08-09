package issues;

using tink.state.Promised;

@:asserts class Issue65 {
  public function new() {}

  public function test() {

    var outer = new Outer();
    asserts.assert(Outer.requests == 0);
    var inner = outer.inner;
    asserts.assert(Outer.requests == 1);

    Observable.auto(() -> outer.inner.id).bind({ direct: true }, function () {});

    asserts.assert(Outer.requests == 1);
    asserts.assert(outer.inner.beep.match(Loading));
    asserts.assert(Outer.requests == 1);

    Outer.advance();

    asserts.assert(outer.inner.beep.match(Done(Noise)));

    asserts.assert(Outer.requests == 1);
    asserts.assert(!Outer.advance());

    asserts.assert(outer.inner == inner);

    return asserts.done();
  }
}

class Outer implements Model {
  static final queue = [];
  static public var requests(default, null) = 0;
  static public function loadNoise():Promise<Noise> {
    var ret = new FutureTrigger<Noise>();
    requests++;
    queue.push(ret);
    return ret;
  }
  static public function advance()
    return switch queue.shift() {
      case null: false;
      case v: v.trigger(Noise);
    }

  @:computed var inner:Inner = new Inner();
}

class Inner implements Model {
  static var counter = 0;
  @:constant var id : Int = counter++;
  @:loaded var beep : Noise = Outer.loadNoise();
  @:constant var cb : CallbackLink = beep.next(o->o).handle( () -> trace("Handled") );

  public function new() {
    beep;
  }
  public function toString()
    return 'Inner#$id';
}