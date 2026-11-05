package helder.pdf;

// Why a PDF was not read or a page not drawn (PdfError.kind), as
// helder.image's ImageError: corrupt (the file contradicts itself or ends
// early), tooLarge (past PdfLimits), unsupported (a feature helder does not
// read), encrypted (a password it was not given)
enum abstract PdfErrorKind(Int) {
	var Corrupt;
	var TooLarge;
	var Unsupported;
	var Encrypted;

	public function toString():String
		return switch (cast this : PdfErrorKind) {
			case Corrupt: "corrupt";
			case TooLarge: "too large";
			case Unsupported: "unsupported";
			case Encrypted: "encrypted";
		}
}

class PdfError extends haxe.Exception {
	public final kind:PdfErrorKind;

	public function new(kind:PdfErrorKind, message:String) {
		super(message);
		this.kind = kind;
	}

	public static inline function corrupt(m:String):PdfError
		return new PdfError(Corrupt, m);

	public static inline function tooLarge(m:String):PdfError
		return new PdfError(TooLarge, m);

	public static inline function unsupported(m:String):PdfError
		return new PdfError(Unsupported, m);
}
