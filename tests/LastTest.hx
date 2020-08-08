@:asserts
class LastTest {
  public function new() {}
  public function test() {
    var w = new WithLast({
      foo: 'foo',
      load: function (s) return if (s.length > 3) s.toUpperCase() else new Error('$s is too short')
    });
    asserts.assert(w.bar == 'foo');
    asserts.assert(w.async.match(Failed(_)));
    w.foo = 'bar';
    asserts.assert(w.bar == 'foobar');
    asserts.assert(w.async.match(Failed(_)));
    w.foo = 'wobble';
    asserts.assert(w.bar == 'foobarwobble');
    asserts.assert(w.async.match(Done('WOBBLE')));
    w.foo = 'boink';
    asserts.assert(w.bar == 'foobarwobbleboink');
    asserts.assert(w.async.match(Done('BOINK')));
    w.foo = 'bop';
    asserts.assert(w.bar == 'foobarwobbleboinkbop');
    asserts.assert(w.async.match(Done('BOINK')));

    return asserts.done();
  }
}

class WithLast implements Model {
  @:editable var foo:String;
  @:constant var load:String->Promise<String>;
  @:computed var bar:String = $last.or('') + foo;
  @:loaded var async:String = load(foo).map(o -> switch [o, $last] {
    case [Success(v), _]: Success(v);
    case [_, Some(v)]: Success(v);
    default: o;
  });
}