package;

@:asserts
class PatchTest {
  public function new() {}

  public function test() {
    var patch:Patch<PatchModel> = {}
    
    // basically just make sure it is a plain object, not a promise
    asserts.assert(patch.foo == null);
    asserts.assert(patch.bar == null);

    return asserts.done();
  }
}

class PatchModel implements Model {
  @:observable var foo:Int;
  @:editable var bar:String;
}