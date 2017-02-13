package ;

import tink.unit.TestRunner.*;
import tink.unit.Assert.*;

import tink.state.Observable;
import tink.state.Promised;

using tink.CoreApi;

class RunTests {

  static function main() {
    run([
        new TodoModelTest(),
    ]).handle(function(result) {
        exit(result.errors);
    });
    // trace('it works');
    // travix.Logger.exit(0); // make sure we exit properly, which is necessary on some targets, e.g. flash & (phantom)js
  }
  
}

class TodoModelTest {
  public function new() {}

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
      @:privateAccess item.__coco_similar.bind({ direct: true }, function (v) {
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

class TodoItem implements coconut.data.Model {

  @:constant var server:{ function loadSimilarTodos(description:String):Promise<Iterable<TodoItem>>; };
  @:constant var created:Date = @byDefault Date.now();
  
  @:editable var completed:Bool = false;
  @:editable var description:String;

  @:computed var firstLine:String = description.split('\n')[0];
  
  @:loaded var similar:Iterable<TodoItem> = server.loadSimilarTodos(this.description);
}

class Server {
  static public function loadSimilarTodos(description:String):Promise<Iterable<TodoItem>>
    return ([]:Iterable<TodoItem>);
}