package;

@:asserts
class ValidationTest {
  public function new() {}

  public function test() {
    new ConstTypeParameter();
    return asserts.done();
  }
}

private class ConstTypeParameter implements Model {
	@:constant var c:Const<255> = null;
	@:constant var ac:AbstractConst = null;
	@:constant var r:Recursive = null;
	@:constant var sr:SelfReferenced<String> = null;
	@:constant var asr:AbstractSelfReferenced = null;
}

private abstract AbstractConst(Const<255>) {}
private typedef Const<@:const P> = String;

private typedef Recursive = {var r(default, never):Recursive;}

private abstract AbstractSelfReferenced(SelfReferenced<AbstractSelfReferenced>) {}
private typedef SelfReferenced<T> = {var self(default, never):T;}