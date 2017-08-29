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
    ])).handle(exit);
  }
  
}

@:asserts
class TransitionTest {
  public function new() {}
  
  public function normal() {
    var model = new TransitionModel();
    
    Promise.inParallel([
      model.modify(1)
        .next(function(_) {
          asserts.assert(model.value == 1);
          return Noise;
        }),
      model.observables.transitionLink.nextTime(function(link) return link != null)
        .next(function(link) {
          asserts.assert(link != null);
          return Noise;
        }),
    ]).handle(function(_) asserts.done());
    
    return asserts;
  }
  
  public function abort() {
    var model = new TransitionModel();
    var transition = model.modify(1);
    asserts.assert(model.transitionLink != null);
    model.transitionLink.dissolve();
    
    transition.handle(function(_) {
      asserts.assert(model.value == 0);
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
  @:describe("external")
  public function external(test:AssertionBuffer) {
    var compass = new Compass(),
        speedometer = new Speedometer();

    var movement:Movement = new Movement({ 
      heading: compass.degrees / 180 * Math.PI,
      speed: speedometer.mph * ONE_MILE_IN_METERS / 3600,
    });
    
    test.assert(movement.heading == 0);
    compass.degrees = 90;
    test.assert(movement.heading == Math.PI / 2);
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

class TodoItem implements coconut.data.Model {

  @:constant var server:{ function loadSimilarTodos(description:String):Promise<Iterable<TodoItem>>; };
  @:constant var created:Date = @byDefault Date.now();
  
  @:constant var whatever:Option<Observable<List<TodoItem>>> = None;
  @:constant var whatever2:Observable<String> = '';
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

class Rates implements coconut.data.Model {
  
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
  @:editable var degrees:Float = @byDefault .0;
}

class Speedometer implements Model {
  @:editable var mph:Float = @byDefault .0;
}

class TransitionModel implements Model {
  @:observable var value:Int = @byDefault 0;
  
  @:transition
  function modify(v:Int)
    return Future.async(function(cb) haxe.Timer.delay(cb.bind({value: v}), 10));
  
  @:transition
  function failure()
    return new Error('Dummy');
}