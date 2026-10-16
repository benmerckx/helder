package hxmc.gfx;

// the depth test: a fragment passes when its depth compares so with the buffer's
enum abstract Compare(Int) {
	var Never;
	var Less;
	var Equal;
	var LessEqual;
	var Greater;
	var NotEqual;
	var GreaterEqual;
	var Always;
}
