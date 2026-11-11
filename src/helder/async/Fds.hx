package helder.async;

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.Posix;
import hxmc.unsafe.UInt8;

// POSIX's calls on descriptors that take memory, over spans: the one place
// helder.async hands the system an address, each call its span's own
// address and length (pipe: a span of two Ints at least), so that their
// callers (Loop's wake pipe, Signals' handler) are checked kernels over
// scratch in their frame. Not on Windows: the callers' branch for it is
// another (Mem.os(), known when compiling, so these are not linked there).
@:hxmc.kernel @:hxmc.unsafe
class Fds {
	// at most b.length bytes read into b: their number, 0 at the end, < 0 on a failure
	public static function read(fd:Int, b:Span<UInt8>):Int
		return Posix.read(fd, (cast b : hxmc.Span.SpanData).ptr, b.length).toInt();

	// b written: the bytes written, < 0 on a failure
	public static function write(fd:Int, b:ReadOnlySpan<UInt8>):Int
		return Posix.write(fd, (cast b : hxmc.Span.SpanData).ptr, b.length).toInt();

	// a pipe, its ends into fds[0] (read) and fds[1] (write): 0, else -1
	public static function pipe(fds:Span<Int>):Int
		return fds.length < 2 ? -1 : Posix.pipe((cast fds : hxmc.Span.SpanData).ptr);
}
#end
