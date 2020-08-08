# Coconut Data

[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/MVCoconut/Lobby)

This library is the meat of the coconut, so to speak. It allows you to model your domain and application state based on the following principles:

1. **All state changes MUST BE observable**. This is achieved by making all data either constant or observable. We'll talk about that [towards the end](#enforced-observability).
2. **Data flow SHOULD BE unidirectional**. Coconut Data does not *enforce* this, because what we're really after is for data flow to be **easy to follow**. Making it unidirectional almost always helps with that. However on occassion there are scenarios in which linearization obscures the data flow instead of simplifying it. Instead of wasting energy on trying to make it hard for you to build cycles into your flow, Coconut Data focusses on giving you powerful tools to avoid having to resort to cycles in the first place.

# Models

A model in coconut is an object that `implements coconut.data.Model`.

Models are quite restrictive about what kind of properties they allow. Currently, there are seven kinds, each of which is designated by special metadata.

- `@:constant` - is initialized upon construction and never changes
- `@:observable` - may change over time with the model's *transtions* (more on those later)
- `@:editable` - may be set from outside.
- `@:computed` - a property computed from the model's state - the last value is accessible as `Option` via `$last`
- `@:loaded` - not unlike a computed property, but the computation is asynchronous - the last value is accessible as `Option` via `$last`
- `@:external` - the module consumes an `Observable` upon construction and exposes it as if it were its own
- `@:shared` - the module consumes a `State` upon construction and exposes it as if it were its own

Properties that are `@:constant`, `@:observable` or `@:editable` are physically existent on the model, while `@:computed` and `@:loaded` are derived values. Let's see how we might use them:

```haxe
class TodoItem implements Model {

  @:constant var created:Date = @byDefault Date.now();
  @:editable var completed:Bool = false;
  @:editable var description:String;

  @:computed var firstLine:String = description.split('\n')[0];
  @:loaded var similar:tink.pure.List<TodoItem> = Server.loadSimilarTodos(this.description);
}
```

By default, the model's constructor is auto generated to accept any of the physical properties (unless they're initialized directly) and to require them if no default is provided. As for `@:computed` and `@:loaded` properties we see that the computation to determine their value is defined on the right side of their declaration.

The above definition will result in a class with the following signature (accessors omitted for simplicity):

```haxe
class TodoItem implements Model {
  public var created(get, never):Date;
  public var completed(get, set):Bool;
  public var description(get, set):String;
  public var firstLine(get, never):String;
  public var similar(get, never):tink.state.Promised<tink.pure.List<TodoItem>>;

  public function new(initial:{ description:String, ?created:Date }):Void { /* magic happens here */}

  public final observables:{
    final created:tink.state.Observable<Date>;
    final completed:tink.state.Observable<Bool>;
    final description:tink.state.Observable<String>;
    final firstLine:tink.state.Observable<String>;
    final similar:tink.state.Observable<tink.state.Promised<tink.pure.List<TodoItem>>>;
  };
}
```

All fields become public by default (you can use `private` to keep them private of course) and all except the `@:editable` ones are readonly.

## `@:loaded` properties

Notice how in the example above the `@:loaded` property we declared actually has it's type promoted to `Promised<T>` from `tink_state` which is defined like so:

```haxe
enum Promised<T> {
  Loading;
  Done(value:T);
  Failed(e:Error);
}
```

Because the computation is asynchronous its current state can assume any of the three values.

### Cache control

... is planned ;)

### Injecting services

To properly modularize your application you will want to avoid having your models depend on services directly as it is in the above example. Instead, try to follow an approach where you provide services from outside, like so:

```haxe
class TodoItem implements Model {
  // ... rest as above

  @:constant var server:{ function loadSimilarTodos(description:String):tink.core.Promise<tink.pure.List<TodoItem>>; };
  @:loaded var similar:tink.pure.List<TodoItem> = server.loadSimilarTodos(this.description);
}
```

And of course you can still specify a default:

```haxe
@:constant var server:{ function loadSimilarTodos(description:String):tink.core.Promise<tink.pure.List<TodoItem>>; } = @byDefault Server;
```

This technique may also make sense for directly `@:computed` properties.

## Observables

You may have noticed the `observables` field, which exposes one observable per each individual field to allow explicitly dealing with `tink_state` observables. It is absolutely safe to ignore and let coconut implicitly propagate changes through your application. Here is how you could use it by hand though:

```haxe
var todo = new TodoItem({ description: 'Hello, World!'});
todo.observables.firstLine.bind({ direct: true }, function (line) trace(line));
todo.description = 'Hello\nWorld!';

//output:
Hello, World!
Hello
```

## Transitions

You may have noticed that there's no way to modify `@:observable` fields directly. This is only possible in a `@:transition function`.

Any such function must return a `Promise<Changes>` where `Changes` is an object containing the fields changed.

Consider this example that might model the different tax / luxury / science rate in Civilization 1:

```haxe
class Rates implements coconut.data.Model {

  @:observable var taxRate:Int = 0;
  @:observable var luxuryRate:Int = 0;
  @:computed var scienceRate:Int = 100 - taxRate - luxuryRate;

  @:transition function setTaxRate(to:Int) {

    if (to < 0) to = 0;
    else if (to > 100) to = 100;

    return
      if (to + luxuryRate < 100) { taxRate: to };
      else { taxRate: to, luxuryRate: 100 - to };
  }

  @:transition function setLuxuryRate(to:Int) {

    if (to < 0) to = 0;
    else if (to > 100) to = 100;

    return
      if (to + taxRate < 100) { luxuryRate: to };
      else { luxuryRate: to, taxRate: 100 - to };
  }
}
```

You may notice that in this case we are returning the state changes synchronously. This works, because promises have an implicit cast from direct values.

### When Type Inference Fails

There are some cases in which type inference leads to types that cannot be implicitly cast to the final type.

Assume we had defined `setTaxRate` like so:

```haxe
@:transition function setTaxRate(to:Int) {

  if (to < 0) to = 0;
  else if (to > 100) to = 100;

  return
    if (to < taxRate || to - taxRate < scienceRate)
      Future.sync(Noise).map(function (_) return { taxRate: to });
    else { taxRate: to, luxuryRate: 100 - to };
}
```

Let's set aside the fact that this is pretty non-sensical of course. The most important point is that because of type inference we will get `tink.core.Future<{ taxRate : Int }> should be tink.core.Promise<{ ?taxRate : Null<Int>, ?luxuryRate : Null<Int> }>`. Unless [the compiler begins understanding that these types are compatible](https://github.com/HaxeFoundation/haxe/issues/6031) for the time being you can prefix the object declaring the updated fields with `@patch`, e.g.:

```haxe
@:transition function setTaxRate(to:Int) {

  if (to < 0) to = 0;
  else if (to > 100) to = 100;

  return
    if (to < taxRate || to - taxRate < scienceRate)
      Future.sync(Noise).map(function (_) return @patch { taxRate: to });
    else { taxRate: to, luxuryRate: 100 - to };
}
```

In addition to that, there's a special `@:genericBuild` type, that will give you the patch type for a given coconut model:

```haxe
var p:Patch<Rates> = {};
$type(p);//{ ?taxRate : Null<Int>, ?luxuryRate : Null<Int> }
```

You can use that if you're in need for an explicit type.

### Returning Values

By default a transition will simply return `Promise<Noise>`. You may however put a return statement into its metadata to return a value computed based on the final state after the transition.

```haxe
@:transition(return taxRate)
function setTaxRate(to:Int) {

  if (to < 0) to = 0;
  else if (to > 100) to = 100;

  return
    if (to < taxRate || to - taxRate < scienceRate)
      Future.sync(Noise).map(function (_) return @patch { taxRate: to });
    else { taxRate: to, luxuryRate: 100 - to };
}
```

Technically you can do things like `@:transition(return Date.now().getTime())` but it's needless to say that you should use this feature to yield information that is useful to the caller. The return type is always a promise, even if your transition happens to be synchronous.

### Synchronization

... is also planned ...

## Comparators

Both `@:editable` and `@:observable` fields support comparators that determine whether two values are considered equal. The previous value is `prev` and the next value is `next`. Example:

```haxe
@:editable(comparator = Type.enumEq(prev, next)) var color:Option<String>;
```

This means that `model.color = Some('pink')` will not trigger if the value already was `Some('pink')`.

## Custom Constructors

It is possible to have custom constructors of two kinds:

1. **without arguments**: in this case the constructor still is generated, and the constructor body supplied by you is executed after the model is initialized. Think of it as a post-construct hook.
2. **with arguments**:

  The structure of such a constructor is as follows:

  ```haxe
  @:constant var foo:Int;
  @:constant var bar:String = @byDefault "bar";
  @:constant var beep:String = "beep";
  @:constant var bop:String = @byDefault "bop";
  function new(arg1:T1, arg2:T2) {
    //any code here is executed prior to initialization and access to `this` results in a compiler error

    this = {//exactly one assignment to `this` is expected in the constructor body and it must contain a value for every property that doesn't have an initial or default value
      foo: 42,
      bar: 'barbar'
    };

    //any code here may now access `this` as the model is now initialized
  }
  ```

## Adding functionality to models on the fly via annex

Every model has a property called `annex` with a method called `get` that is to be called with a model class that must have a constructor which will accept the model as its parameter. Example:

```haxe
class Todo implements Model {
  @:editable var done:Bool;
  @:editable var description:String;
}

class TodoList implements Model {
  @:observable var items:List<Todo> = @byDefault null;
  @:transition function add(description)
    return { items: items.append(new Todo({ done: false, description: description })) };
}

class TodoSelection implements Model {
  @:editable var filter:Todo->Bool = function (_) return true;
  @:constant private var todos:TodoList;
  @:computed var items:List<Todo> = todos.items.filter(function (item) return filter(item));
  @:computed var total:Int = todos.items.length;
  @:computed var selected:Int = items.length;
  public function new(todos:TodoList)
    this = { todos: todos };
}
```

If you have a `var todoList = new TodoList()`, then calling `todoList.annex.get(TodoSelection)` will return the same `TodoSelection` every time (it is created when requested the first time and then retained).

This only makes sense, if you want the same associated state for the same model everywhere.

### Static extensions with annex

It is sometimes useful to combine static extensions with annex, e.g.:

```haxe
class TodoListTools {
  static public function select(todoList:TodoList, filter)
    todoList.get(TodoSelection).filter = filter;
  static public function selectedItems(todoList:TodoList)
    return todoList.get(TodoSelection).items;
}
```

And when `using TodoListTools`, you can do `todoList.select(i -> i.done)` and retrieve `todoList.selectedItems()`.

# To cycle or not to cycle

When you can, you should not build cycles in your data. Let's look at an example of a cycle:

```haxe
class Car implements coconut.data.Model {
  @:constant var driver:Driver = new Driver({ car: this });
}

class Driver implements coconut.data.Model {
  @:constant var car:Car;
}
```

This is merely a cycle in your object graph and not yet in your data flow. It has problems of its own, but let's bring it to full catastrophy:

```haxe
class Car implements coconut.data.Model {
  @:constant var driver:Driver = new Driver({ car: this });
  @:computed var isInsured:Bool = driver.isInsured;
}

class Driver implements coconut.data.Model {
  @:constant var car:Car;
  @:computed var isInsured:Bool = car.isInsured;
}
```

Access `new Car().isInsured` and you'll get a stack overflow.

That said, you could do it differently:

```haxe
class Car implements coconut.data.Model {
  @:constant var driver:Driver = new Driver({ car: this });
  @:constant var insurance:Option<Insurance> = None;
  @:computed var isInsured:Bool = switch [insurance, car.insurance] {
    case [None, None]: false;
    default: true;
  }
}

class Driver implements coconut.data.Model {
  @:constant var car:Car;
  @:constant var insurance:Option<Insurance> = None;
  @:computed var isInsured:Bool = car.isInsured;
}
```

There's still a lot of circular referencing going on though and that makes it easy to create circular computations that recurse into a stack overflow.

What's more is though that this is not even necessarily a good model of cars and drivers. This might be a nice way to describe it instead:

```haxe
class Car implements coconut.data.Model {
  @:constant var insurance:Option<Insurance> = None;
}
class Driver implements coconut.data.Model {
  @:constant var insurance:Option<Insurance> = None;
}
class Trip implements coconut.data.Model {
  @:constant var car:Car;
  @:constant var driver:Driver;
  @:computed var isInsured:Bool = switch [driver.insurance, car.insurance] {
    case [None, None]: false;
    default: true;
  }
}
```

And suddenly nothing is circular anymore. You simply incarnate the relationship between a car and its driver as a first class object. This is idea is not exactly new. In relational algebra complex relationships are often modelled by separate entities, thus avoiding cycles. Imagine the opposite: a database where the car references the driver and the driver references the car. If you want to undo the relationship, you have to update two records and you have to do it in a transaction (assume your database supports these) which tends to be rather expensive.

So again: if you have a complex relationship, make that a separate model and declare any `@:computed` properties as needed. If any of the source objects change, the computed property will update. For free. Even if you have data associated with some object, there's no need to keep it *in the object*.

```haxe
class Car implements coconut.data.Model {
  @:observable var licensePlate:String;
}

class OutstandingWarrants implements coconut.data.Model {
  @:constant var car:Car;
  @:loaded var warrants:tink.pure.List<Warrant> = Database.getWarrants(car.licensePlate);
}
```

So you can do `var check = new OutstandingWarrants({car: someCar })` and as soon as the `someCar.licensePlate` you get a new result from `check.warrants`.

## Cycles in Transitions

It is also easy to create cycles with transitions. Calling `driver.stop()` calls `car.stop()` calls `driver.stop()` and so on. Using the above technique to have unidirectional object graphs of lean objects is a good way to avoid running into such a situation. Still, down the line virtually all applications are *inherently* loops. Usually the loop is closed through the UI invoking callbacks it was given that map down to transitions. But at times the loops might be fundamentally baked into the domain/application model. This is ok, but if you have hundreds of them you should really take a hard look at how many of them are really necessary.

One way to avoid getting caught up in a dense jungle of transitions is to eliminate transitions when possible (with reasonable effort). Imagine we have an application in which we model the user and login like so:

```haxe
typedef Credentials = {
  final user:String;
  final password:String;
}

typedef Server = {
  function login(with:Credentials):Promise<UserProfile>;
}

class User implements coconut.data.Model {
  @:constant var server:Server;
  @:observable var profile:Option<UserProfile> = None;

  @:transition function login(with:Credentials)
    return server.login(with).next(function (p) return { profile: Some(p) });
}
```

Guests have `None` as their `profile` and logged in users have `Some(value)` of course. By calling `login` we can transition from one state to the other. That is one way to express it. But instead, we might do the following:

```haxe
class User implements coconut.data.Model {
  @:constant var server:Server;
  @:editable var credentials:Option<Credentials>;
  @:loaded var profile:Option<UserProfile> = switch credentials {
    case None: None;
    case Some(c): server.login(c).next(profile -> Some(profile));
  }
}
```

And just like that we've eliminated a transition. Whether or not it's smart to do in this particular case is a fair question. The lesson to be learnt from this example: asynchronous operations can be seen as transitions from one state to another, but in some cases the can be expressed as mere computations. Just for reference, here's an example of something that is definitely a transition:

```haxe
class User implements coconut.data.Model {
  @:constant var store:{ function buy(item:Item):Promise<{ total:Int }> };
  @:observable var balance:Int = 100;
  @:transition function buy(item:Item)
    return
      if (item.price < balance) store.buy(item).next(function (o) return { balance: balance - o.total });
      else {};
}
```

The difference here is: you can log in 100 times with the same credentials, the result will be the same - unless they change in the meantime or your connection or the server goes down or the server engages some flood control after 3 attempts ... but for the sake of the argument let's just say the result will be the same. If for some reason the `profile` field had to be reloaded with the same credentials it is quite safe to assume the result would be the same. However when you buy an item in the store, things change. Sooner or later you're out of money or the store is out of stock.

# Enforced Observability

Coconut does its best to try enforcing every field of a model holding a value which is observable, where immutable values are treated as a special case of observability (a particularly trivial one at that). The following types are thus considered observable:

- `Int`, `Float`, `Bool`, `String`, `Date`
- Any type decorated with `@:pure` or `@:observable`
- Any enum for which all constructors are observable
- Any subtype of `coconut.data.Model`
- Any subtype of `tink.state.Observable.ObservableObject` (thus including `State` and `Observable`)
- Any function - this is a bit of a stretch
- Any anonymous object who's fields all have observable type and write access `never`
- Any type parameter - because this is hard to check

This leaves a couple of type holes. For example `Iterator<Int>` will slip through, even though clearly it is neither constant nor observable.

This is an area deserving of improvement, but without a some help from Haxe itself to determine immutability, very little progress is to be expected. Note thought that in `coconut.ui` a second pass of checks is performed, thus closing *some* of the type holes created by type parameters.

You can always tag a type `@:pure` or `@:observable` to feed data into coconut, that it would not consider acceptable otherwise. You may also add `@:skipCheck` on a model's field to bypass the check. Note that misuse of these features can lead to a situation where state changes are not properly propagated through you application.

# Model Composition

While `coconut.data` currently does not support model inheritance, `@:external` fields provide a very powerful approach to composition.

Imagine this:

```haxe
class Movement implements Model {

  @:external var heading:Float;
  @:external var speed:Float;

  @:computed var horizontalSpeed:Float = Math.cos(heading) * speed;
  @:computed var verticalSpeed:Float = Math.sin(heading) * speed;

  @:computed var velocity:Vec2 = new Vec2(horizontalSpeed, verticalSpeed);

}
```

So this model of movement gives us a couple of properties based on speed and heading. Let's assume we have something that gives us speed and heading:

```haxe
class Compass implements Model {
  @:observable var degrees:Float;
}

class ChipLog implements Model {
  @:observable var knots:Float;
}
```

And let's compose these:

```haxe
var compass:Compass = ...;
var log:ChipLog = ...;
var movement = new Movement({
  heading: compass.degrees / 180 * Math.PI,
  speed: log.knots * KNOTS_IN_METERS_PER_SECOND,
});
```

As we see, we can easily get data from multiple sources, transform it on the fly (degrees to radians and mph to m/s) and compose it into a new model. Notice though that `Movement` does not in any way depend on either a compass or a chip log. If you're not on a boat, you may wish to procure your data by different means.

To explain in a bit more detail what's happening with each of the external fields, let's examine the `heading`. What this does is add a `heading : coconut.data.Value<Float>` to the constructor argument's fields. The `Value<T>` is a helper, that will directly consume any `Observable<T>` but will wrap any other expression in [`Observable.auto`](https://github.com/haxetink/tink_state#automagic-observables). The observable is consumed by the constructor and is directly exposed, making it opaque to the outside world whether the very origin of the data is *within* the model or external to it.
