# The site

The website built with `@hxmc/web` (site/), as hxmc's
docs/development.md described it until the split (hxmc a994ea3); hxmc now
has a plain static site of its own.


`make site` builds `bin/site`; any static server shows it (`npx http-server
bin/site`), and `make site-check` tests it in headless Chromium, Firefox and
WebKit (Playwright with its browsers; `BROWSERS=chromium` for one). The
pages are components rendered at build time by `site/src` with
`@hxmc/web`'s static renderer, on the tool's Eval (`Site.hx`; it runs
natively too); the same run:

- builds each package example for the browser: every file of a package's
  `examples/` that starts with a header (`// title:`, `// summary:`,
  `// tags:`, `// demo: canvas WxH`, `sound`, `island` or `module`) is a
  card of the examples page, built for wasm32-wasi with its package's class
  paths (`Examples.hx`) and shown as a WebAssembly island next to its
  source and the files of its folder it uses; the ui and text programs get
  DejaVu Sans (`fonts-dejavu-core`);
- renders the docs from the repository's Markdown (`Docs.hx`,
  `Markdown.hx`: `docs/*.md`, `README.md`, `ROADMAP.md`, the plans, each
  package's README and ui's guide; links between them become links between
  the pages, any other file a link to GitHub);
- reads the packages' API with the tool (`Api.hx`: their modules typed
  together, `--json`, and the `//` comment above each public declaration
  read from its source);
- measures the hxmc page's sizes and cold build times (`Measure.hx`: three
  programs for the seven targets);
- copies the packages' browser modules and the island loader.

Then the Makefile adds the playground's compiler (`bin/wasm`), the
JavaScript (`site/build.hxml`, compiled by the port: `site.js`, every
page's islands; `lab.js` and `counter.js`, the examples'; the playground's
and the tables' scripts), the std the playground reads, the data and the
build facts, and prints each page's weight (`site/tools/weights.mjs`). Every
file a page loads carries the commit in its address (`?v=`: `Site.asset`,
`Version.hx`). CI builds it in the `site` job, tests it in `playground` and
deploys it from main in `pages`.

