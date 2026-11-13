import hxmc.Span;

// helder's typed C bindings (hxmc's @:hxmc.safe with @:hxmc.header: Fds, Sig)
// reached by one program, lowered only, for the header-check lane: hxmc
// writes them as assertions over the system's headers, zig compiles those
class HeaderCheck {
	@:hxmc.kernel static function pipe():Int {
		var fds:Span<Int> = Span.stack(2);
		return helder.async.Fds.pipe(fds);
	}

	@:hxmc.callback @:hxmc.kernel static function handler(sig:Int):Void {}

	static function main() {
		var b = haxe.io.Bytes.alloc(8);
		var r = helder.async.Fds.read(0, Span.ofBytes(b));
		var w = helder.async.Fds.write(1, hxmc.ReadOnlySpan.ofBytes(b));
		var old = helder.async.Fds.Sig.signal(15, handler);
		trace(pipe(), r, w, old);
	}
}
