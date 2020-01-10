package issues;

@:asserts
class Issue53 {
  public function new() {
  }
  public function test() {
    var a:coconut.data.Value<Int>;
    a = 42;
    asserts.assert(a.value == 42);
    return asserts.done();
  }
}