package issues;

class Issue66 {
  public function new() {}
}
class FooModel<@:skipCheck A, B> implements Model {}

class BarModel implements Model {
  @:constant var foo:FooModel<Array<Int>, String>;
}