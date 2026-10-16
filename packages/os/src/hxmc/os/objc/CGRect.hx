package hxmc.os.objc;

// CoreGraphics' geometry (CGFloat is a double on 64-bit targets); AppKit's
// NSPoint, NSSize and NSRect are the same structs. They go by value in
// messages (Msg): homogeneous aggregates of doubles, in float registers.
@:hxmc.struct @:publicFields class CGRect {
	var origin:CGPoint;
	var size:CGSize;
}
