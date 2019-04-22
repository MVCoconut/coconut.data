package coconut.data;

@:autoBuild(coconut.data.macros.Models.build())
interface Model {}

@:noCompletion abstract FunctionReference<T>(T) from T to T {}