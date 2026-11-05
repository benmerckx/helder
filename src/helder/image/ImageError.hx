package helder.image;

// Why a file was not decoded (ImageError.kind)
enum abstract ImageErrorKind(Int) {
	// not a format helder reads, or a feature of it that is not decoded
	// (arithmetic-coded JPEG, 12-bit samples)
	var Unsupported;
	// malformed or truncated: what its header or data says cannot be
	var Corrupt;
	// larger than ImageLimits allows (its pixels, a side, or the memory
	// its decode would take)
	var TooLarge;

	public function toString():String
		return switch (cast this : ImageErrorKind) {
			case Unsupported: "unsupported";
			case Corrupt: "corrupt";
			case TooLarge: "too large";
		}
}

// What every decoder of helder.image throws (Image.decode, the decoders'
// decode and frames, AnimatedImage.decode): its kind and a message naming
// the decoder ("GifDecoder: a frame larger than allowed (70000x70000)").
// Nothing else escapes a decoder: an index out of a hostile file's range
// is Corrupt.
class ImageError extends haxe.Exception {
	public final kind:ImageErrorKind;

	public function new(kind:ImageErrorKind, message:String) {
		super(message);
		this.kind = kind;
	}

	public static inline function corrupt(message:String):ImageError
		return new ImageError(Corrupt, message);

	public static inline function unsupported(message:String):ImageError
		return new ImageError(Unsupported, message);

	public static inline function tooLarge(message:String):ImageError
		return new ImageError(TooLarge, message);
}
