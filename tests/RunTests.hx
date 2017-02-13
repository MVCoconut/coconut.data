package ;

class RunTests {

  static function main() {
    // trace('it works');
    // travix.Logger.exit(0); // make sure we exit properly, which is necessary on some targets, e.g. flash & (phantom)js
  }
  
}

class TodoItem implements coconut.data.Model {
  
  @:constant var created:Date = @byDefault Date.now();
  
  @:editable var completed:Bool = false;
  @:editable var description:String;

  @:computed var firstLine:String = description.split('\n')[0];
  
  @:loaded({ eagerly: true }) var similar:Iterable<TodoItem> = Server.loadSimilarTodos(this.description);
}