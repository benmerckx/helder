package helder.image;

#if (target.name == "hxmc")
// (hxmc 0.1.0-nightly.20261028.409f580: with -dce full, which helder build
// passes, the lowering of a span's accesses finds hxmc.Span's SpanData
// without its fields, which no typed code reads: "@:hxmc.struct SpanData
// has no field ptr". Read here, kept, until hxmc keeps them itself.)
@:keep class SpanDce {
	@:keep @:hxmc.unsafe static function fields(d:hxmc.Span.SpanData):Int
		return d.length + (d.ptr.isNull() ? 0 : 1);
}
#end
