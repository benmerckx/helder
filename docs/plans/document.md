# Documents: PDF, SVG and images as a platform

A view rendered to a document instead of a window: `Document.render(view,
{page: A4})` gives PDF, SVG or pixels. A document is a platform like any
other, with no events: a host that lays out at the page size and paints
each page through a `Canvas`. The writers are packages (`@hxmc/pdf`, with
SVG beside it), pure Haxe, on every target. Reading PDFs (pdf.js-style)
would draw through the same Canvas.

## What today's API must already allow

These land now, before more code builds on the current `Canvas`, so the
document platform needs no breaking change later:

- **Host apart from Canvas.** The environment a tree runs in (size, DPI,
  fonts, events, the clock, focus) is a host; drawing is a Canvas. A host
  with no events and a fixed size is first-class (documents, headless
  tests, thumbnails), not a fake window.
- **A vector Canvas.** Besides `rect`, `shadow`, `image` and `text`:
  `path` (a path of moves, lines, quadratic and cubic curves, arcs and
  closes; filled by non-zero or even-odd, and stroked with width, caps,
  joins, miter and dashes) and paints that are gradients (linear, radial,
  conic; stops) as well as colours, for fills, strokes and borders. SVG
  icons and the theme's icons reach the Canvas as paths, not bitmaps.
- **Text as glyph runs.** `text` takes runs, each with its font (a
  reference a writer can embed and subset), size, glyph ids, positions and
  the source text of each cluster, plus decorations. The GPU renderer
  rasterizes them; a PDF embeds subsets with `ToUnicode` (searchable,
  copyable); SVG writes `<text>` or paths.
- **Images keep their source.** An `Image` keeps its encoded bytes and type
  when it has them, so a writer can embed a JPEG or PNG as it is.
- **Effects say what they are.** Shadows, blur and opacity groups stay
  calls of their own (not pre-rasterized), so each output picks how: SVG
  filters, a raster of just that call in a PDF.
- **Semantics next to drawing.** A node's link (`href`) and its place in
  the accessibility tree reach the host: link annotations and a tagged
  PDF, `<a>` and ARIA in SVG.
- **Paged layout's names reserved.** `break-before`, `break-after`,
  `break-inside` and page size/margins exist in `Style` (no effect on a
  window), so markup written now prints later.

## Later

- Paged layout: fragmenting the tree across pages (breaks, orphans and
  widows, table headers repeated, headers and footers per page), each page
  a Canvas pass.
- `@hxmc/pdf`: the object writer (streams through `haxe.zip`), font
  subsetting from `hxmc.text`'s TrueType and CFF, images, links, outlines,
  tagged structure, metadata; SVG output; PNG through the GPU renderer's
  headless readback.

## Who builds what

The Canvas, host and Style changes above are `packages/ui`'s (the UI
session), done now; the document host, paged layout and `@hxmc/pdf` come
later, here.
