package issues;


class Issue51 implements coconut.data.Model {
  @:constant var color:Hsv = null;
}

abstract Hsv(Base) {}

@:pure
abstract Base(Array<Float>) {}