package ;

import tink.testrunner.Runner.*;
import tink.unit.*;
import tink.unit.Assert.*;

import tink.state.*;
import tink.state.Promised;
import coconut.data.*;

using tink.CoreApi;

class RunTests {

  static function main() {
    run(TestBatch.make([
      new TransitionTest(),
      new ExternalTest(),
      new TodoModelTest(),
      new SelectionTest(),
      new CustomConstructorTest(),
      new LastTest(),
    ])).handle(exit);
    var a:InitialArgs<TransitionModel> = {};
    a = { value: 12 };
    a = {};
    
  }
  
}

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

@:asserts
class CustomConstructorTest {
  public function new() {}
  
  public function normal() {
    asserts.assert(WithPostConstruct.constructed == 0);
    new WithPostConstruct();
    new WithPostConstruct();
    asserts.assert(WithPostConstruct.constructed == 2);
    var w = new WithCustomConstructor(42, 123);
    asserts.assert(w.sum == 165);
    return asserts.done();
  }
}

@:asserts
class TransitionTest {
  public function new() {}
  
  public function normal() {
    var model = new TransitionModel();
    
    asserts.assert(!model.isInTransition);
    var transition = model.modify(1);
    asserts.assert(model.isInTransition);
    transition.handle(function(_) {
      asserts.assert(model.value == 1);
      asserts.assert(!model.isInTransition);
      asserts.done();
    });
    
    return asserts;
  }
  
  public function error() {
    var model = new TransitionModel();
    var errorEmitted = false;
    model.transitionErrors.handle(function(_) errorEmitted = true);
    return model.failure().map(function(_) return assert(errorEmitted));
  }
}

class ExternalTest {
  public function new() {}
  static inline var ONE_MILE_IN_METERS = 1600;//or something

  public function external(test:AssertionBuffer) {
    var mph = new State(.0);
    var compass = new Compass(),
        speedometer = new Speedometer({ mph: mph });

    function mphToMps(mph:Float)
      return mph * ONE_MILE_IN_METERS / 3600;

    var movement:Movement = new Movement({ 
      heading: compass.degrees / 180 * Math.PI,
      speed: mphToMps(speedometer.mph),
    });
    
    test.assert(movement.heading == 0);
    compass.degrees = 90;
    test.assert(movement.heading == Math.PI / 2);
    compass.degrees += 360;
    test.assert(movement.heading == Math.PI / 2);
    
    test.assert(movement.speed == 0);
    speedometer.mph = 100 / mphToMps(1);
    test.assert(movement.speed == 100);
    mph.set(10);
    test.assert(movement.speed == mphToMps(mph.value));

    return test.done();
  }

  public function defaults(test:AssertionBuffer) {
    var m = new RandomExternals({ foo: "foofoo", bar: 12 });
    test.assert(m.foo == "foofoo");
    test.assert(m.bar == 12);

    var m = new RandomExternals();
    test.assert(m.foo == "foo");
    test.assert(m.bar == 0);
    RandomExternals.tick.trigger(Noise);
    RandomExternals.tick.trigger(Noise);
    test.assert(m.bar == 2);
    return test.done();
  }
}

class SelectionTest {
  
  static var options = [for (i in 0...10) new Named(Std.string(i), i)];
  
  public function new() {}

  @:describe("single selection")
  @:describe("  without unselect")
  public function singleWithoutUnselect(test:AssertionBuffer) {
    var s = Selection.single(options);

    test.assert(s.selected == None);
    
    for (v in options) {
      test.assert(s.toggle(v.value));
      test.assert(Type.enumEq(Some(v.value), s.selected));
      test.assert(s.toggle(v.value));
      test.assert(Type.enumEq(Some(v.value), s.selected));
    }

    return test.done();
  }

  @:describe("  with unselect")
  public function singleWithUnselect(test:AssertionBuffer) {
    var s = Selection.single(options, { canUnselect: true });

    test.assert(s.selected == None);
    
    for (v in options) {
      test.assert(s.toggle(v.value));
      test.assert(Type.enumEq(Some(v.value), s.selected));
      test.assert(!s.toggle(v.value));
      test.assert(s.selected == None);
      test.assert(s.toggle(v.value));
    }

    return test.done();
  }  

  @:describe("  non-optional")
  public function testNonOptional(test:AssertionBuffer) {
    var s = Selection.of(options[0]).or(options.slice(1));

    for (v in options) {
      test.assert(s.toggle(v.value));
      test.assert(v.value == s.selected);
      test.assert(s.toggle(v.value));
    }

    return test.done();
  }

  @:describe("multiple selection")
  public function testMultiple(test:AssertionBuffer) {

    var s = Selection.multiple(options);
    for (v in options) {
      test.assert(s.toggle(v.value));
      test.assert(!s.toggle(v.value));
      test.assert(s.toggle(v.value));
    }
    test.assert(options.length == s.selected.length);
    return test.done();
  }
}

class TodoModelTest {
  public function new() {}

  @:describe("@:transition") 
  public function testTransitions(test:AssertionBuffer) {
    var rates = new Rates();
    var p:Patch<Rates> = {};
    p = { taxRate: 50 };
    p = { luxuryRate: 50 };
    p = { luxuryRate: 50, taxRate: 50 };
    var o:ObservablesOf<Rates> = rates.observables;
    o.taxRate.bind({ direct: true }, function (t) test.assert(rates.taxRate == t));
    function checksum()
      test.assert(rates.taxRate + rates.luxuryRate + rates.scienceRate == 100);

    checksum();

    rates.setTaxRate(50);

    test.assert(rates.taxRate == 50);
    test.assert(rates.luxuryRate == 0);
    
    checksum();

    for (i in 0...20) {
      rates.setLuxuryRate(Std.random(200) - 50);
      checksum();
      rates.setTaxRate(Std.random(200) - 50);
      checksum();
    }
    var sum = 0;

    rates.setTaxRate(40).handle(function (o) sum += o.sure());
    rates.setLuxuryRate(30).handle(function (o) sum += o.sure());
    
    test.assert(sum == 70);

    checksum();

    return test.done();
  }

  @:describe("@:loaded")
  public function testLoaded(test:AssertionBuffer) {
    
    var called = false,
        empty:Iterable<TodoItem> = [];
    function loadSimilarTodos(description:String):Promise<Iterable<TodoItem>> {
      called = true;
      var ret = Future.async(function (cb) {
        haxe.Timer.delay(cb.bind(empty), 100);
      });
      ret.handle(function (o) trace(o));
      return ret;
    }

    var item = new TodoItem({ description: 'test', server: {loadSimilarTodos:loadSimilarTodos} }),
        expected = [Loading, Done(empty)];
        
    Future.async(function (cb) {
      if (called) {
        cb(Failure(new Error('@:loaded is not lazy')));
        return;
      }
      item.observables.similar.bind({ direct: true }, function (v) {
        var e = expected.shift();
        if (!called)
          cb(Failure(new Error('@:loaded did not start loading')));
        if (!Type.enumEq(e, v))
          cb(Failure(new Error('Expected $e but found $v')));

        if (expected.length == 0)
          cb(Success(Noise));
      });
    }).handle(function (o) {
      test.assert(o.isSuccess());
      test.done();
    });

    return test;
  }

}

enum Foople {
  Froz(a:Array<Int>);
}
@:observable enum Foople2 {
  Froz2(a:Array<Int>);
}

class RandomExternals implements Model {
  @:external var foo:String = @byDefault "foo";
  @:external var bar:Int = @byDefault {
    var s = new State(0);
    tick.handle(function () s.set(s.value + 1));
    s;
  }
  static public var tick = new SignalTrigger<Noise>();
}

class TodoItem implements Model {

  @:constant var server:{ function loadSimilarTodos(description:String):Promise<Iterable<TodoItem>>; };
  @:constant var created:Date = @byDefault Date.now();
  
  @:constant var whatever:Option<Observable<List<TodoItem>>> = None;
  @:constant var whatever2:Observable<String> = Observable.const('');
  @:skipCheck @:constant var whatever3:Array<String> = [];
  @:skipCheck @:constant var whatever4:Foople = Froz([]);
  @:constant var whatever5:Foople2 = Froz2([]);

  @:constant var array:ObservableArray<Int> = null;
  @:constant var map:ObservableMap<String, Int> = null;
  
  @:editable var completed:Bool = false;
  @:editable var description:String;

  @:computed var firstLine:String = description.split('\n')[0];
  
  @:loaded var similar:Iterable<TodoItem> = server.loadSimilarTodos(this.description);
}

class Server {
  static public function loadSimilarTodos(description:String):Promise<Iterable<TodoItem>>
    return ([]:Iterable<TodoItem>);
}

class Rates implements Model {
  
  @:observable var taxRate:Int = 0;
  @:observable var luxuryRate:Int = 0;
  @:computed var scienceRate:Int = 100 - taxRate - luxuryRate;

  @:transition(return taxRate) 
  function setTaxRate(to:Int) {
    
    if (to < 0) to = 0;
    else if (to > 100) to = 100;

    return 
      if (to < taxRate || to - taxRate < scienceRate) Future.sync(Noise).map(function (_) return @patch { taxRate: to });
      else { taxRate: to, luxuryRate: 100 - to };
  }

  @:transition(return luxuryRate) 
  function setLuxuryRate(to:Int) {
    
    if (to < 0) to = 0;
    else if (to > 100) to = 100;

    return 
      if (to < luxuryRate || to - luxuryRate < scienceRate) { luxuryRate: to };
      else { luxuryRate: to, taxRate: 100 - to };
  }  
}

class Ticker {
  static public function make(rate:Float = 1) {
    var timer = new haxe.Timer(Std.int(1000 / rate));
    var ret = new State(0);
    timer.run = function () ret.set(ret.value + 1);
    return ret.observe();
  }
}

class Movement implements Model {
  
  @:external var heading:Float;
  @:external var speed:Float;
  
  @:computed var horizontalSpeed:Float = Math.cos(heading) * speed;
  @:computed var verticalSpeed:Float = Math.sin(heading) * speed;

  @:computed var velocity:Vec2 = new Vec2(horizontalSpeed, verticalSpeed);

}

@:pure class Vec2 {
  public function new(x, y) {}
}

class Compass implements Model {
  @:editable(guard = (next % 360 + 360) % 360) var degrees:Float = @byDefault .0;
}

class Speedometer implements Model {
  @:shared var mph:Float = @byDefault new State(.0);
}

class TransitionModel implements Model {
  @:observable var value:Int = @byDefault 0;
  @:signal var boink:String;
  @:transition
  function modify(v:Int) {
    _boink.trigger('blub');
    return Future.async(function(cb) haxe.Timer.delay(cb.bind({value: v}), 10));
  }
  
  @:transition
  function failure()
    return new Error('Dummy');
}

class WithCustomConstructor implements Model {
  @:observable var sum:Int;
  function new(a:Int, b:Int) {
    // log('sum ${this.sum}');//shouldn't compile
    this = { sum: a + b };
  }
}

class WithPostConstruct implements Model {
  static public var constructed(default, null):Int = 0;
  function new() {
    constructed++;
  }
}

class WithLast implements Model {
  @:editable var foo:String;
  @:constant var load:String->Promise<String>;
  @:computed var bar:String = $last.or('') + foo;
  @:loaded var async:String = load(foo).map(o => switch [o, $last] {
    case [Success(v), _]: Success(v);
    case [_, Some(v)]: Success(v);
    default: o;
  });
}