package coconut.data;

import tink.state.*;

@:forward
abstract Variable<T>(State<T>) from State<T> to State<T> {
    //TODO: add `@:from macro` magic similar to `Value`
}