# helder.pdf

PDF reading and rendering on helder.canvas, from leanpdf
(alineacms/leanpdf, MIT, TypeScript) as the basis: its split of the
reader (lexer, xref, recovery, streams and filters, the standard security
handler) and the renderer (the content stream interpreter, colour
spaces, functions, shadings, images, fonts as outlines), brought to Haxe
and drawing on any `helder.canvas.Painter` (the CPU's Canvas, the GPU's,
the browser's canvas, a recording) instead of Canvas 2D. Not a line-by-line
port.

```haxe
var doc = helder.pdf.Pdf.open(bytes);          // Document; PdfError when it is not one
var page1 = helder.pdf.Pdf.render(doc, 0, 2);  // a premultiplied Bitmap at 2 pixels a point
helder.pdf.Pdf.draw(doc.pages[3], painter, 1.5);
```

- **Reading** (`Document`, `Parser`): the xref table or stream at
  startxref and those it chains to (/Prev, /XRefStm), each offset once;
  object streams; a stream's /Length checked against its endstream; a file
  whose xref is missing or wrong rebuilt from its `n g obj` headers (the
  trailer, or an xref stream's dictionary, or the catalog). The page tree
  with what pages inherit (resources, boxes, rotation).
- **Filters** (`Filters`): FlateDecode (haxe.zip's inflate; raw deflate
  too) and LZWDecode with PNG and TIFF predictors, ASCIIHexDecode,
  ASCII85Decode, RunLengthDecode; DCTDecode through helder.image's JPEG
  decoder. JPXDecode, CCITTFaxDecode and JBIG2Decode are not decoded yet
  (an Unsupported error; the page's other content drawn).
- **Encryption** (`Crypto`): the standard handler with the empty user
  password (or one given): RC4 40 to 128 bits, AES-128 (AESV2), AES-256
  (R5 and R6: SHA-256, and R6's hash 2.B with SHA-384 and SHA-512), each
  object's key; AES, RC4 and SHA-512 here, checked against FIPS vectors.
- **Rendering** (`Interpreter`): the graphics state, paths, both fill
  rules, strokes (dashes, joins, caps, a width under a pixel as one pixel, as
  viewers draw it), clips,
  colours in DeviceGray, RGB and CMYK (pdf.js's fitted
  conversion), CalGray, CalRGB, Lab,
  ICCBased (by its alternate), Indexed, Separation and DeviceN (their tint
  transform), functions of types 0, 2, 3 and 4 (PostScript), axial and
  radial shadings (sh and shading patterns) as gradients, tiling patterns
  (the cell drawn on the CPU, repeated), images (1 to 16 bits, Decode,
  /SMask, stencil masks, colour keys, image masks; an enlarged image's
  samples unsmoothed unless /Interpolate), inline images, form XObjects
  (their matrix and bounding box, a transparency group's opacity and blend
  mode as a layer), ExtGState's opacities, blend modes and line styles;
  annotations by their normal appearance (/AP /N, its /AS state) in their
  /Rect, form fields' widgets among them, hidden ones left out.
- **Text** (`PdfFont`): simple and composite fonts, encodings (Standard,
  WinAnsi, MacRoman, /Differences; glyph names to Unicode), ToUnicode
  (bfchar, bfrange: `Pdf.text(page)`, a substitute face's characters), /Widths and
  /W, CMaps (codespaces, cid ranges; Identity-H and -V), the text state
  (spacing, scaling, rise, leading, every render mode, clipping by text);
  glyphs as outlines from the embedded program: TrueType and OpenType
  (helder.text's FontFile, a subset with no Unicode cmap read all the
  same; a symbolic font's (3,0) and (1,0) cmaps), bare
  CFF and CID-keyed CFF (helder.text's Cff, the charset read here), Type 1
  (`Type1`: eexec, charstrings, subrs, seac, flex), Type 3 (its glyph
  procedures run); a font not embedded from the system by its name
  (Liberation's metric-compatible faces first), fitted to the file's widths.
- **Images, sized to the page**: a JPEG decoded reduced by its DCT's
  scaling (1/2 to 1/8) to no fewer pixels than it is shown at, a JPEG 2000
  by whole resolution levels (`Jpx`, ported from leanpdf), any other image
  twice its shown size or more averaged down after decoding; CCITT G3 and
  G4 (`Ccitt`, ported from leanpdf). On the web back end glyphs are kept
  in the page as Path2D (helder.canvas's GlyphCache) and drawn by key.
- **Decoded images kept** per document (`Document.images`, an LRU bounded
  by `PdfLimits.imageCache`, 64 MB by default): by an image's reference and
  the size it is shown at, so a page drawn again decodes nothing; on the web
  the browser's images (`PdfWeb.prepare`: JPEGs decoded by the browser at
  the size shown, before a synchronous `Pdf.draw`).
- **What is linked**: `Pdf.open` links decryption (`Crypto`) and JPEG
  2000; `Pdf.openPlain` neither, nor helder's JPEG decoder (`Pdf.render` and
  `PdfImage.useJpeg` link it; with `PdfWeb.prepare` the browser decodes),
  the smaller build. Pattern cells are drawn by the
  painter's own kind (`Painter.offscreen`) and `Pdf.text` by no painter, so
  a web build carries no CPU rasterizer.
- **Limits** (`PdfLimits`, as helder.image's ImageLimits): objects, a
  stream's bytes and the document's decoded total (a decompression
  budget), pages, nesting of objects, forms and patterns, operators a page
  runs, an image's pixels; every bound checked before the work, every
  failure a typed `PdfError` (corrupt, too large, unsupported, encrypted).
- Not yet: soft masks (/SMask in an ExtGState), function-based and mesh
  shadings, optional content, JBIG2Decode (an image in it left out), the writing half
  (merging, selecting pages, compressing).

The image viewer opens PDFs too (apps/viewer: page 1, at the size shown).

Tests: the pdf lane (page 1 of each corpus file, tests/pdf/corpus made by
ReportLab, pypdf, LibreOffice and by hand: corpus.py; a scanned page,
CJK text, a 120-page document, form fields among them; against pdf.js's
in Chromium: pdfjs.mjs, tests/pdf/ref; check.mjs: of the 3x3 blocks either
inks at most 10% apart, and the text against pdf.js's getTextContent;
15 of 15; tests/pdf/known.txt lists pages expected to fail, none now), the pdf-fuzz
lane (the corpus mutated for 30 s, each mutant ending in pixels or a
PdfError: about 13,000 mutants, none otherwise), Crypto.test.hx (the test
lane).
