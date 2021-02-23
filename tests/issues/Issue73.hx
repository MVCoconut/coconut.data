package issues;

@:asserts
class Issue73 {
  public function new() {}
  public function test() {
    var m = new TestModel({data: "false"});
    asserts.assert(m.values.value == "a");
    return asserts.done();
  }
}

class TestModel implements Model {
  @:external var data:String;
  @:constant var values:Faulty = new Faulty({ someBool: someBool });
  @:computed var someBool:Bool = true;
}

class Faulty implements Model {
  @:external var someBool:Bool;
  @:observable var value:String = "none";
  @:transition function boom()
    return someBool ? {value:"a"} : {};

  public function new() {
    boom();
  }
}