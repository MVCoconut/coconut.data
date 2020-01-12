package issues;

@:asserts
class Issue37 {
  public function new() {}
  public function test() {
    new Minimal({list: []});
    return asserts.done();
  }
}

class Minimal implements Model {
  @:constant var list:tink.pure.List<String>;
  @:constant var child:MinimalChild = new MinimalChild({list:list});
}

class MinimalChild implements Model {
  @:external var list:tink.pure.List<String>;
}