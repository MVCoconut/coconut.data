package ;

import tink.testrunner.Runner.*;
import tink.unit.*;


class RunTests {

  static function main() {
    run(TestBatch.make([
      new issues.Issue2(),
      new issues.Issue37(),
      new issues.Issue42(),
      new issues.Issue46(),
      new issues.Issue51(),
      new issues.Issue53(),
      new issues.Issue57(),
      new issues.Issue65(),
      new examples.Civ1(),
      new examples.TodoModelTest(),
      new TransitionTest(),
      new ExternalTest(),
      new SelectionTest(),
      new CustomConstructorTest(),
      new LastTest(),
      new ValidationTest(),
      new VariableTest(),
      new ObservabilityTest(),
      new PatchTest(),
    ])).handle(exit);
  }

}

class Stuff implements Model {
  // issue #12:
    @:editable var foo:MyEnum = MyEnum.None;
    @:editable var bar:MyEnum2 = None;

  //issue #36
    @:editable var thisIsFine:ThisIsFine = null;

  @:signal var string:String;
  @:editable var nullable:Null<Int>;
}

@:skipCheck class ThisIsFine {}

enum MyEnum {
  None;
  Some(e:MyEnum);
}

typedef MyEnum2 = Option<MyEnum2>;