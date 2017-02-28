package ;

import tink.unit.TestRunner.*;
import tink.unit.Assert.*;

import tink.state.Observable;
import tink.state.Promised;
import coconut.data.*;

using tink.CoreApi;

class RunTests {

  static function main() {
    run([
      new TodoModelTest(),
      new SelectionTest(),
    ]).handle(function(result) {
      exit(result.errors);
    });
  }
  
}

class SelectionTest {
  
  static var options = [for (i in 0...10) new Named(Std.string(i), i)];
  
  public function new() {}

  @:describe("single selection")
  @:describe("  without unselect")
  public function singleWithoutUnselect() {
    
    var ret = isTrue(true);

    function assert(b:Bool, ?pos:haxe.PosInfos)
      ret = ret && isTrue(b, pos);

    var s = Selection.single(options);
    assert(s.selected == None);
    for (v in options) {
      assert(s.toggle(v.value));
      assert(Type.enumEq(Some(v.value), s.selected));
      assert(s.toggle(v.value));
      assert(Type.enumEq(Some(v.value), s.selected));
    }
    return ret;
  }

  @:describe("  with unselect")
  public function singleWithUnselect() {
    
    var ret = isTrue(true);

    function assert(b:Bool, ?pos:haxe.PosInfos)
      ret = ret && isTrue(b, pos);

    var s = Selection.single(options, { canUnselect: true });
    assert(s.selected == None);
    for (v in options) {
      assert(s.toggle(v.value));
      assert(Type.enumEq(Some(v.value), s.selected));
      assert(!s.toggle(v.value));
      assert(s.selected == None);
      assert(s.toggle(v.value));
    }
    return ret;
  }  

  @:describe("  non-optional")
  public function testNonOptional() {

    var ret = isTrue(true);

    function assert(b:Bool, ?pos:haxe.PosInfos)
      ret = ret && isTrue(b, pos);
    
    var s = Selection.of(options[0]).or(options.slice(1));

    for (v in options) {
      assert(s.toggle(v.value));
      assert(v.value == s.selected);
      assert(s.toggle(v.value));
    }

    return ret;
  }

  @:describe("multiple selection")
  public function testMultiple() {

    var ret = isTrue(true);

    function assert(b:Bool, ?pos:haxe.PosInfos)
      ret = ret && isTrue(b, pos);

    var s = Selection.multiple(options);
    for (v in options) {
      assert(s.toggle(v.value));
      assert(!s.toggle(v.value));
      assert(s.toggle(v.value));
    }
    assert(options.length == s.selected.length);
    return ret;
  }
}

class TodoModelTest {
  public function new() {}

  @:describe("@:transition") 
  public function testTransitions() {
    var rates = new Rates();
    

    var ret = isTrue(true);

    function checksum()
      ret = ret && equals(100, rates.taxRate + rates.luxuryRate + rates.scienceRate);

    checksum();

    rates.setTaxRate(50);

    ret = ret && equals(50, rates.taxRate);
    ret = ret && equals(0, rates.luxuryRate);
    
    checksum();

    for (i in 0...100) {
      rates.setLuxuryRate(Std.random(200) - 50);
      checksum();
      rates.setTaxRate(Std.random(200) - 50);
      checksum();
    }
    var sum = 0;

    rates.setTaxRate(40).handle(function (o) sum += o.sure());
    rates.setLuxuryRate(30).handle(function (o) sum += o.sure());
    
    ret = ret && equals(70, sum);

    checksum();

    return ret;
  }

  @:describe("@:loaded")
  public function testLoaded() {
    
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
    return Future.async(function (cb) {
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
    });
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