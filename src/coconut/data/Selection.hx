package coconut.data;

using tink.CoreApi;

class Selection<T, R> implements Model {
  
  @:editable private var active:List<T> = null;

  @:constant var options:List<Named<T>>;

  @:constant private var reduce:List<T>->R;
  @:constant private var toggler:List<T>->T->List<T>;
  @:constant private var comparator:T->T->Bool = function (x, y) return x == y;
  
  @:computed var selected:R = reduce(active);

  public function isActive(option:T)
    return active.exists(comparator.bind(option));

  public function isEnabled(option:T):Bool
    return true;

  public function toggle(option:T):Bool {

    this.active = toggler(this.active, option);

    return isActive(option);
  }

  static public function single<T>(options:List<Named<T>>, ?settings:{ ?canUnselect:Bool}):Selection<T, Option<T>>
    return
       new Selection({
        options: options,
        reduce: function (l) return l.first(),
        toggler: 
          switch settings {
            case null | { canUnselect: null | false }:
              function (_, nu) return [nu];
            default:
              function (old, nu) return switch old.first() {
                case Some(v) if (v == nu): [];
                default: [nu];
              }
          }
      });

  static public function of<T>(init:Named<T>):{ function or(rest:List<Named<T>>):Selection<T, T>; }
    return {
      or: function (rest) {
        var ret = new Selection({
          options: rest.prepend(init),
          reduce: function (l):T return l.iterator().next(),
          toggler: function (_, nu) return [nu],
        });
        ret.toggle(init.value);
        return ret;
      } 
    }

  static public function multiple<T>(options:List<Named<T>>):Selection<T, List<T>> {
    return new Selection({
      options: options,
      reduce: function (l) return l,
      toggler: 
        function (old, nu) return 
          switch old.filter(function (i) return i != nu) {
            case same if (same.length == old.length): old.prepend(nu);
            case v: v;
          },
    });
  }
}