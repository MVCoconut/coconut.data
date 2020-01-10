@:asserts
class ExternalTest {
  public function new() {}
  static inline var ONE_MILE_IN_METERS = 1600;//or something

  public function external() {
    var mph = new State(.0);
    var compass = new Compass(),
        speedometer = new Speedometer({ mph: mph });

    function mphToMps(mph:Float)
      return mph * ONE_MILE_IN_METERS / 3600;

    var movement:Movement = new Movement({
      heading: compass.degrees / 180 * Math.PI,
      speed: mphToMps(speedometer.mph),
    });

    asserts.assert(movement.heading == 0);
    compass.degrees = 90;
    asserts.assert(movement.heading == Math.PI / 2);
    compass.degrees += 360;
    asserts.assert(movement.heading == Math.PI / 2);

    asserts.assert(movement.speed == 0);
    speedometer.mph = 100 / mphToMps(1);
    asserts.assert(movement.speed == 100);
    mph.set(10);
    asserts.assert(movement.speed == mphToMps(mph.value));

    return asserts.done();
  }

  public function defaults() {
    var m = new RandomExternals({ foo: "foofoo", bar: 12 });
    asserts.assert(m.foo == "foofoo");
    asserts.assert(m.bar == 12);

    var m = new RandomExternals();
    asserts.assert(m.foo == "foo");
    asserts.assert(m.bar == 0);
    RandomExternals.tick.trigger(Noise);
    RandomExternals.tick.trigger(Noise);
    asserts.assert(m.bar == 2);
    return asserts.done();
  }
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
  @:editable(guard = (param % 360 + 360) % 360) var degrees:Float = @byDefault .0;
}

class Speedometer implements Model {
  @:shared var mph:Float = @byDefault new State(.0);
}