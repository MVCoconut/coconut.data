package issues;

class Issue46 {
  public function new() {

  }
}

class Issue46Model implements Model {
  @:loaded var somethingAmazing:Int = {
    if (incredibleProperty == 0) calculatePlanToConquerWorld($last.or(0));
    else if (incredibleProperty == 1) haveBreakfastBeforeConqueringTheWorld($last.or(0));
    else conquerWorld();
  };

  @:editable private var incredibleProperty:Int = -1;

  function calculatePlanToConquerWorld(whoKnows:Int) return Future.sync(1);
  function haveBreakfastBeforeConqueringTheWorld(whoKnows:Int) return Future.sync(2);
  function conquerWorld() return 42;
}