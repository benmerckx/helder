package hxmc.gfx;

// What the back ends keep of a texture (their tables of it), and the checks
// they share: a descriptor's, a write's region (resolved into w and h), a
// pass's targets.
class TextureInfo {
	public final width:Int;
	public final height:Int;
	public final format:TextureFormat;
	public final levels:Int;
	public final target:Bool; // a render target
	// the last region checked (checkWrite)
	public var w = 0;
	public var h = 0;

	function new(width:Int, height:Int, format:TextureFormat, levels:Int, target:Bool) {
		this.width = width;
		this.height = height;
		this.format = format;
		this.levels = levels;
		this.target = target;
	}

	// a descriptor's texture (TextureDesc): its levels counted, its data checked
	public static function of(d:TextureDesc):TextureInfo {
		var w = d.width, h = d.height, data = d.data, levels = d.mipLevels;
		var format:TextureFormat = d.format == null ? RGBA8 : d.format;
		var full = 1;
		while ((w | h) >> full != 0)
			full++;
		if (levels == null) levels = 1 else if (levels == 0) levels = full;
		var target = d.renderTarget == true || format.depth;
		if (w <= 0 || h <= 0 || levels < 1 || levels > full || data != null && (target || data.length < w * h * format.texelSize))
			throw "hxmc.gfx: createTexture: an empty size, more mip levels than the size has, data for a render target or too little data";
		return new TextureInfo(w, h, format, levels, target);
	}

	public inline function levelWidth(level:Int):Int
		return width >> level > 0 ? width >> level : 1;

	public inline function levelHeight(level:Int):Int
		return height >> level > 0 ? height >> level : 1;

	// a write of the region w x h at x, y of the level (w < 0: all of it)
	// from data at dataOffset: throws when it does not fit; then w and h
	public function checkWrite(data:haxe.io.Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int) {
		if (target || level < 0 || level >= levels) throw "hxmc.gfx: writeTexture: a render target, or no such mip level";
		var lw = levelWidth(level), lh = levelHeight(level);
		if (w < 0) {
			w = lw;
			h = lh;
		}
		if ((x | y | h | dataOffset) < 0 || x + w > lw || y + h > lh || dataOffset + w * h * format.texelSize > data.length)
			throw "hxmc.gfx: writeTexture: outside the texture or the data";
		this.w = w;
		this.h = h;
	}

	// (generateMips)
	public function checkMips()
		if (!format.filterable) throw "hxmc.gfx: generateMips: not of a filterable format";

	// (beginPass) a colour texture of a pass, and the pass's depth: a texture
	public function checkPass(depth:DepthTarget)
		if (!target || depth != null && depth.texture == null) throw "hxmc.gfx: beginPass: not into a render target, or without a depth texture";
}
