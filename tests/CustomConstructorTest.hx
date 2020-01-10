@:asserts
class CustomConstructorTest {
  public function new() {}

  public function normal() {
    asserts.assert(WithPostConstruct.constructed == 0);
    new WithPostConstruct();
    new WithPostConstruct();
    asserts.assert(WithPostConstruct.constructed == 2);
    var w = new WithCustomConstructor(42, 123);
    asserts.assert(w.sum == 165);
    return asserts.done();
  }
}

class WithPostConstruct implements Model {
  static public var constructed(default, null):Int = 0;
  function new() {
    constructed++;
  }
}

class WithCustomConstructor implements Model {
  @:observable var sum:Int;

  function new(a:Int, b:Int) {
    // log('sum ${this.sum}');//shouldn't compile
    this = { sum: a + b };
  }
}
