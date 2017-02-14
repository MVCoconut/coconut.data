# Coconut Data

This library is the meat of the coconut, so to speak. It allows you to model your domain and application state based on the following principles:

1. **All state changes MUST BE observable**. This is achieved by making all data either constant or observable. We'll talk about that in a moment.
2. **Data flow SHOULD BE unidirectional**. Coconut Data does not *enforce* this, because the what we're really after is for data flow to be **easy to follow**. Making it unidirectional almost always helps with that. However on occassion there are scenarios in which linearization obscures the data flow instead of simplifying it. Instead of wasting energy on trying to make it hard for you to build cycles into your flow, Coconut Data focusses on giving you powerful tools to avoid having to resort to cycles in the first place.

# Models

A model in coconut is an object that `implements coconut.data.Model`.

Models are quite restrictive about what kind of properties they allow. Currently, there are five kinds, each of which is designated by special metadata.

- `@:constant` - is initialized upon construction and never changes
- `@:observable` - may change over time with the model's *transtions* (more on those later)
- `@:editable` - may be set from outside.
- `@:computed` - a property computed from the model's state
- `@:loaded` - not unlike a computed property, but the computation is asynchronous

The first three are physically existent on the model, while the latter two are dependent values. Let's see how we might use them:

```haxe
class TodoItem implements Model {
  
  @:constant var created:Date = @byDefault Date.now();
  @:editable var completed:Bool = false;
  @:editable var description:String;

  @:computed var firstLine:String = description.split('\n')[0];
  @:loaded var similar:Iterable<TodoItem> = Server.loadSimilarTodos(this.description);
}
```

The model's constructor is auto generated to accept any of the physical properties (unless they're initialized directly) and to require them if no default is provided. As for `@:computed` and `@:loaded` properties we see that the computation to determine their value is defined on the right side of their declaration.

This will result in a class with the following signature (accessors omitted for simplicity):

```haxe
class TodoItem implements Model {
  public var created(get, never):Date;
  public var completed(get, set):Bool;
  public var description(get, set):String;
  public var firstLine(get, never):String;
  public var similar(get, never):tink.state.Promised<Iterable<TodoItem>>;

  public function new(initial:{ description:String, ?created:Date }):Void { /* magic happens here */}

  public var observable(default, never):{
    var created(default, never):tink.state.Observable<Date>;
    var completed(default, never):tink.state.Observable<Bool>;
    var description(default, never):tink.state.Observable<String>;
    var firstLine(default, never):tink.state.Observable<String>;
    var similar(default, never):tink.state.Observable<tink.state.Promised<Iterable<TodoItem>>>;
  };
}
```

All fields become public by default (you can use `private` to keep them private of course) and all except the `@:editable` ones are readonly. 

## `@:loaded` properties

Notice how in the example above the `@:promised` property we declared actually has it's type promoted to `Promised<T>` from `tink_state` which is defined like so:

```haxe
enum Promise<T> {
  Loading;
  Done(value:T);
  Failed(e:Error);
}
```

### Cache control

... is planned ;)

#### Injecting services

To properly modularize your application you will want to avoid depend your modules on services directly as it is on the example. Instead you will want a setup that is more like this:

```haxe 
class TodoItem implements Model {
  // ... rest as above

  @:constant var server:{ function loadSimilarTodos(description:String):tink.core.Promise<Iterable<TodoItem>>; };
  @:promised var similar:Iterable<TodoItem> = server.loadSimilarTodos(this.description);
}
```

And of course you can still do `@:constant var server:{ function loadSimilarTodos(description:String):tink.core.Promise<Iterable<TodoItem>> = @byDefault Server; };`.

This technique may also make sense for directly `@:computed` properties.

#### Observables

You may notice the `observable` field, which exposes an observable for each individual field to allow explicitly dealing with `tink_state` observables. It is absolutely safe to ignore and let coconut implicitly propagate changes through your application. Here is how you could use it by hand though:

```haxe
var todo = new TodoItem({ description: 'Hello, World!'});
todo.observable.firstLine.bind({ direct: true }, function (line) trace(line));
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
      if (to < taxRate || to - taxRate < scienceRate) { taxRate: to };
      else { taxRate: to, luxuryRate: 100 - to };
  }

  @:transition function setLuxuryRate(to:Int) {
    
    if (to < 0) to = 0;
    else if (to > 100) to = 100;

    return 
      if (to < luxuryRate || to - luxuryRate < scienceRate) { luxuryRate: to };
      else { luxuryRate: to, taxRate: 100 - to };
  }  
}
```

You may not that in this case we are return the next state directly, which is also possible since promises have an implicit cast from direct values.

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

### Returning Values

By default a transition will simply return the changes it made. You may however put a return statement into its metadata to return a value computed based on the final state after the transition.

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

Technically you can do things like `@:transition(return Date.now().getTime())` but it's needless to say that you should use this feature to yield information that is useful to the caller.

## To cycle or not to cycle

When you can, you should not build cycles in your data.

First, how do you build cycles:

```haxe
class Car implements coconut.data.Model {
  @:constant var driver:Driver = new Driver({ car: this });
}

class Driver implements coconut.data.Model {
  @:constant var car:Car;
}
```

This is merely a cycle in your object graph and not yet in your data flow. It's bad enough as it is, but let's bring it to full catastrophy:

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

That said you could do it differently:

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

There's still a lot of cyclical referencing going on though and its easily to create cyclical computation that blow up.

What's more is though that this is not even necessarily a good model of cars and drivers. This might be a nice way to discribe it instead:

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

### Cycles in Transitions

It is also easy to create cycles with transitions. Calling `driver.stop()` calls `car.stop()` calls `driver.stop()` and so on. Using the above technique to have unidirectional object graphs of lean objects is a good way to avoid running into such a situation. Note virtually all applications are *inherently* loops. Usually the loop is closed through the UI invoking callbacks it was given that map down to transitions. But at times the loops might be fundamentally baked into the domain/application model.

Note that there's also often a way to eliminate transitions. It's not always desirable though.

Imagine this:

```haxe
typedef Credentials = {
  var user(default, never):String;
  var password(default, never):String;
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

Instead, we might do the following:

```haxe
class User implements coconut.data.Model {
  @:constant var server:Server;
  @:editable var credentials:Option<Credentials>;
  @:loaded var profile:Option<UserProfile> = switch credentials {
    case None: None;
    case Some(c): server.login(with);
  }
}
```

And just like that we've eliminated a transition. Whether or not it's smart to do in this case is a fair question.