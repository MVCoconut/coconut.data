package issues;

@:asserts
class Issue42 {
  public function new() {}
  public function test() {
    var model = new Issue42Model();
    asserts.assert(model.foo == 42);
    model.setFoo(12);
    asserts.assert(model.foo == 12);
    return asserts.done();
  }
}

class Issue42Model implements Model {
  @:editable var foo:Int = 42;
  @:transition function setFoo(value)
    return { foo: value };

}