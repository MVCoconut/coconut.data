package coconut.data;

#if !macro
@:autoBuild(coconut.data.macros.Models.build())
#end
interface Model {}

@:noCompletion abstract FunctionReference<T>(T) from T to T {}