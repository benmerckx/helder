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
  rules, strokes (dashes, joins, caps, a zero width as one pixel), clips,
  colours in DeviceGray, RGB and CMYK (naive), CalGray, CalRGB, Lab,
  ICCBased (by its alternate), Indexed, Separation and DeviceN (their tint
  transform), functions of types 0, 2, 3 and 4 (PostScript), axial and
  radial shadings (sh and shading patterns) as gradients, tiling patterns
  (the cell drawn on the CPU, repeated), images (1 to 16 bits, Decode,
  /SMask, stencil masks, colour keys, image masks; an enlarged image's
  samples unsmoothed unless /Interpolate), inline images, form XObjects
  (their matrix and bounding box, a transparency group's opacity and blend
  mode as a layer), ExtGState's opacities, blend modes and line styles.
- **Text** (`PdfFont`): simple and composite fonts, encodings (Standard,
  WinAnsi, MacRoman, /Differences; glyph names to Unicode), /Widths and
  /W, CMaps (codespaces, cid ranges; Identity-H and -V), the text state
  (spacing, scaling, rise, leading, every render mode, clipping by text);
  glyphs as outlines from the embedded program: TrueType and OpenType
  (helder.text's FontFile; a symbolic font's (3,0) and (1,0) cmaps), bare
  CFF and CID-keyed CFF (helder.text's Cff, the charset read here), Type 1
  (`Type1`: eexec, charstrings, subrs, seac, flex), Type 3 (its glyph
  procedures run); a font not embedded from the system by its name
  (Liberation's metric-compatible faces first), fitted to the file's widths.
- **Limits** (`PdfLimits`, as helder.image's ImageLimits): objects, a
  stream's bytes and the document's decoded total (a decompression
  budget), pages, nesting of objects, forms and patterns, operators a page
  runs, an image's pixels; every bound checked before the work, every
  failure a typed `PdfError` (corrupt, too large, unsupported, encrypted).
- Not yet: soft masks (/SMask in an ExtGState), function-based and mesh
  shadings, optional content, annotations' appearances, the writing half
  (merging, selecting pages, compressing).

The image viewer opens PDFs too (apps/viewer: page 1, at the size shown).

Tests: the pdf lane (page 1 of each corpus file, tests/pdf/corpus made by
ReportLab, pypdf, LibreOffice and by hand: corpus.py, against pdf.js's in
Chromium: pdfjs.mjs, tests/pdf/ref; 9 of 9 within tolerance), the pdf-fuzz
lane (the corpus mutated for 30 s, each mutant ending in pixels or a
PdfError: about 13,000 mutants, none otherwise), Crypto.test.hx (the test
lane).
