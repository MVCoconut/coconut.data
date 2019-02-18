package;

@:asserts
class ValidationTest {
  public function new() {}
  
  public function test() {
    new ConstTypeParameter({t: 'test', a: 'test'});
    return asserts.done();
  }
}

private class ConstTypeParameter implements coconut.data.Model {
	@:constant var t:TypeDef<255>;
	@:constant var a:Abstract;
}

private abstract Abstract(TypeDef<255>) from String {}
private typedef TypeDef<@:const P> = String;