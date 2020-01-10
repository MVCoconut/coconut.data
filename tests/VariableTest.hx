@:asserts
class VariableTest {
  static var source = new Source();
  public function new() {}
  public function test() {
    var c1 =
      #if tink_hxx
        Plain.hxx('<Consumer foo=${source.foo} />');
      #else
        new Consumer({ foo: Variable.make(source.foo) });
      #end
    var c2 =
      #if tink_hxx
        Plain.hxx('<Consumer foo=${source.oof} />');
      #else
        new Consumer({ foo: Variable.make(source.oof) });
      #end
    asserts.assert(c1.foo == '123');
    asserts.assert(c2.foo == '321');

    source.foo = 'yohoho';

    asserts.assert(c1.foo == 'yohoho');
    asserts.assert(c2.foo == 'ohohoy');

    c1.foo = '123';

    asserts.assert(c1.foo == '123');
    asserts.assert(c2.foo == '321');

    c2.foo = '123';

    asserts.assert(c1.foo == '321');
    asserts.assert(c2.foo == '123');

    return asserts.done();
  }
}

private class Source implements Model {
  @:editable var foo:String = '123';
  public var oof(get, set):String;
    function get_oof()
      return reverse(foo);
    function set_oof(param) {
      foo = reverse(param);
      return oof;
    }

  static public function reverse(s:String) {
    var a = s.split('');
    a.reverse();
    return a.join('');
  }
}

private class Consumer implements Model {
  @:shared var foo:String;
}