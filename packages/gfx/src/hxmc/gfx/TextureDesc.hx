package hxmc.gfx;

// a 2D texture a shader samples (one level; Device.writeTexture updates it)
typedef TextureDesc = {
	width:Int,
	height:Int,
	format:TextureFormat,
	?filter:Filter,
	// the initial contents, rows top to bottom, tightly packed (else zeros)
	?data:haxe.io.Bytes
}
