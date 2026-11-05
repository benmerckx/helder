package helder.pdf;

// What reading and drawing a PDF may take, each checked before the work
// it bounds: the file's objects, a stream's decoded bytes and all of a
// document's together (a decompression budget), the pages, the depth of
// nested forms and patterns, the operators a page runs, an image's pixels.
// Defaults for untrusted files; a viewer may raise them.
class PdfLimits {
	public var maxObjects = 2_000_000;
	public var maxStream = 256 << 20;
	public var maxDecoded = 1 << 30;
	public var maxPages = 100_000;
	public var maxDepth = 16;
	public var maxOperators = 20_000_000;
	public var maxImagePixels = 100_000_000;
	public var maxNesting = 64;

	public function new() {}

	public static final DEFAULT = new PdfLimits();
}
