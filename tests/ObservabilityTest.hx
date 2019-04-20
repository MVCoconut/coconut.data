@:asserts
class ObservabilityTest {
	public function new() {}
	
	public function inst() {
		new Container();
		return asserts.done();
	}
}

class Container implements coconut.data.Model {
	#if haxe4
	@:constant var f:Final = null;
	#end
	@:constant var v:NeverWrite = null;
}

private class Object implements coconut.data.Model {}

#if haxe4
private class Final {
	final i:Int = 0;
	final b:Bool = false;
	final f:Float = 0.;
	final s:String = '';
	final o:Object = null;
}
#end

private class NeverWrite {
	var i(default, never):Int;
	var b(default, never):Bool;
	var f(default, never):Float;
	var s(default, never):String;
	var o(default, never):Object;
}

