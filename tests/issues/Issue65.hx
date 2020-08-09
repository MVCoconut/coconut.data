package issues;

@:asserts class Issue65 {
  public function new() {}

  public function test() {

    var outer = new Outer();
    var inner = outer.inner;

    Observable.auto(() -> outer.inner.id).bind({ direct: true }, function () {});
    for (i in 0...100)
      Outer.advance();
    asserts.assert(Outer.requests == 1);
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

  public function new() {
    beep;
  }
  public function toString()
    return 'Inner#$id';
}