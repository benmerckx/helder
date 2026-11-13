package helder.async;

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
import hxmc.I64;
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.UInt8;

// POSIX's calls on descriptors that take memory, as typed bindings over
// spans (hxmc's @:hxmc.safe: each reads or writes only its span, within its
// length), so that their callers (Loop's wake pipe, Signals' handler) are
// checked kernels over scratch in their frame; checked against unistd.h
// (-D hxmc.header-check). Not on Windows: the callers' branch for it is
// another (Platform.os(), known when compiling, so these are not linked there).
@:hxmc.c @:hxmc.fast @:hxmc.safe @:hxmc.header("unistd.h")
extern class Fds {
	static function read(fd:Int, buf:Span<UInt8>):I64;
	static function write(fd:Int, buf:ReadOnlySpan<UInt8>):I64;
	@:hxmc.len(fds, 2) static function pipe(fds:Span<Int>):Int;
}
#end
