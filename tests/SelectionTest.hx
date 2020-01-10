@:asserts
class SelectionTest {

  static var options = [for (i in 0...10) new Named(Std.string(i), i)];

  public function new() {}

  @:describe("single selection")
  @:describe("  without unselect")
  public function singleWithoutUnselect() {
    var s = Selection.single(options);

    asserts.assert(s.selected == None);

    for (v in options) {
      asserts.assert(s.toggle(v.value));
      asserts.assert(Type.enumEq(Some(v.value), s.selected));
      asserts.assert(s.toggle(v.value));
      asserts.assert(Type.enumEq(Some(v.value), s.selected));
    }

    return asserts.done();
  }

  #if ((haxe_ver < 4) && interp) @:exclude #end // FIXME: stack overflow for the old interpreter
  @:describe("  with unselect")
  public function singleWithUnselect() {
    var s = Selection.single(options, { canUnselect: true });

    asserts.assert(s.selected == None);

    for (v in options) {
      asserts.assert(s.toggle(v.value));
      asserts.assert(Type.enumEq(Some(v.value), s.selected));
      asserts.assert(!s.toggle(v.value));
      asserts.assert(s.selected == None);
      asserts.assert(s.toggle(v.value));
    }

    return asserts.done();
  }

  #if((haxe_ver < 4) && php) @:exclude #end // php was buggy in haxe3
  @:describe("  non-optional")
  public function testNonOptional() {
    var s = Selection.of(options[0]).or(options.slice(1));

    for (v in options) {
      asserts.assert(s.toggle(v.value));
      asserts.assert(v.value == s.selected);
      asserts.assert(s.toggle(v.value));
    }

    return asserts.done();
  }

  @:describe("multiple selection")
  public function testMultiple() {

    var s = Selection.multiple(options);
    for (v in options) {
      asserts.assert(s.toggle(v.value));
      asserts.assert(!s.toggle(v.value));
      asserts.assert(s.toggle(v.value));
    }
    asserts.assert(options.length == s.selected.length);
    return asserts.done();
  }
}
