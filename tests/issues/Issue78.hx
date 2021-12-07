package issues;

@:asserts
class Issue78 {
  public function new() {}
  
  @:include
  public function test() {
    var m = new Issue78Model(42);
    asserts.assert(m.foo == 43);
    asserts.assert(m.bar == 44);
    return asserts.done();
  }
}

class Issue78Model implements Model {
  @:constant var foo:Int;
  
  @:computed var bar:Int = foo + 1;
  
  public function new(foo:Int) {
        this = { foo: foo + 1 }
    }
}