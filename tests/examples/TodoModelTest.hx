package examples;

@:asserts
class TodoModelTest {
  public function new() {}

  public function loaded() {

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

    var item = new TodoItem({ description: 'asserts', server: {loadSimilarTodos:loadSimilarTodos} }),
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
      asserts.assert(o.isSuccess());
      asserts.done();
    });

    return asserts;
  }

}

enum Foople {
  Froz(a:Array<Int>);
}
@:observable enum Foople2 {
  Froz2(a:Array<Int>);
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