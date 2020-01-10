package examples;

@:asserts
class Civ1 {
  public function new() {}
  #if ((haxe_ver < 4) && interp) @:exclude #end // FIXME: stack overflow for the old interpreter
  public function transitions() {
    var rates = new Rates();
    var p:Patch<Rates> = {};
    p = { taxRate: 50 };
    p = { luxuryRate: 50 };
    p = { luxuryRate: 50, taxRate: 50 };
    var o:ObservablesOf<Rates> = rates.observables;
    o.taxRate.bind({ direct: true }, function (t) asserts.assert(rates.taxRate == t));
    function checksum()
      asserts.assert(rates.taxRate + rates.luxuryRate + rates.scienceRate == 100);

    checksum();

    rates.setTaxRate(50);

    asserts.assert(rates.taxRate == 50);
    asserts.assert(rates.luxuryRate == 0);

    checksum();

    for (i in 0...20) {
      rates.setLuxuryRate(Std.random(200) - 50);
      checksum();
      rates.setTaxRate(Std.random(200) - 50);
      checksum();
    }
    var sum = 0;

    rates.setTaxRate(40).handle(function (o) sum += o.sure());
    rates.setLuxuryRate(30).handle(function (o) sum += o.sure());

    asserts.assert(sum == 70);

    checksum();

    return asserts.done();
  }
}

class Rates implements Model {

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