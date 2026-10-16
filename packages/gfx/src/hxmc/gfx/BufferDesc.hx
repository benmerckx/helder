package hxmc.gfx;

// Descriptors (*Desc) are built once at init (allocating there is fine).
typedef BufferDesc = {
	size:Int,
	usage:BufferUsage,
	// the initial contents (size bytes from its start)
	?data:haxe.io.Bytes
}
