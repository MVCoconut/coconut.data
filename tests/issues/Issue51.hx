package issues;


class Issue51 {
  public function new() {}
}

class Issue51Model implements Model {
  @:constant var color:Hsv = null;
}

abstract Hsv(Base) {}

@:pure
abstract Base(Array<Float>) {}