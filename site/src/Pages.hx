import Examples.Example;
import Layout.*;
import hxmc.view.*;
import hxmc.web.*;
import sys.FileSystem;

using StringTools;

// The site's pages, each a component rendered by Site.renderPage
class Pages implements Markup {
	static final NIGHTLY = "https://github.com/benmerckx/hxmc/releases/download/nightly/";
	static final TOOLS = "https://haxe-in-haxe.ben.mk/tools/";

	public static function all(examples:Array<Example>, api:Api) {
		var measured = Site.tool != null ? Measure.run() : [];
		Site.renderPage("index.html", () -> Static.document(<Home examples={examples}/>));
		Site.renderPage("compiler.html", () -> Static.document(<Compiler/>));
		Site.renderPage("hxmc.html", () -> Static.document(<Hxmc measured={measured} examples={examples}/>));
		Site.renderPage("packages.html", () -> Static.document(<Packages examples={examples}/>));
		Site.renderPage("examples.html", () -> Static.document(<ExamplesPage examples={examples}/>));
		Site.renderPage("playground.html", () -> Static.document(<Playground/>));
		Site.renderPage("story.html", () -> Static.document(<Story/>));
		Docs.all(api);
	}

	// --- numbers the pages quote, from the measured data ---

	static function bench():Dynamic
		return haxe.Json.parse(Site.read("site/data/bench.json"));

	static function result(b:Dynamic, workload:String, runner:String):Dynamic {
		for (r in (b.results : Array<Dynamic>))
			if (r.workload == workload && r.runner == runner && r.status == "ok") return r;
		return null;
	}

	static function fixed(x:Float, digits:Int):String {
		var m = Math.pow(10, digits);
		var s = Std.string(Math.round(x * m) / m);
		if (digits > 0 && s.indexOf(".") < 0) s += "." + [for (_ in 0...digits) "0"].join("");
		return s;
	}

	public static function kb(bytes:Int):String
		return bytes >= 1 << 20 ? fixed(bytes / (1 << 20), 1) + " MB" : Math.round(bytes / 1024) + " KB";

	static function example(examples:Array<Example>, id:String):Null<Example>
		return Lambda.find(examples, e -> e.id == id);

	// a wasm example's island (the cube on the home page, every card of the
	// gallery), its id demo-<example>: hxmcWasm's and hxmcWasmOptions' key
	public static function Demo(props:{e:Example, ?load:Island.Load, ?children:Any}):View {
		var e = props.e;
		return switch e.demo {
			case Canvas(w, h):
				<Island.Wasm src={e.wasm == null ? 'examples/${e.id}.wasm' : e.wasm} id={"demo-" + e.id} imports={Examples.imports(e.pkg)} fonts={Examples.fonts(e.pkg)}
					width={w} height={h} load={props.load}>{props.children}</Island.Wasm>;
			case Sound:
				<Island.Wasm src={e.wasm == null ? 'examples/${e.id}.wasm' : e.wasm} id={"demo-" + e.id} imports={Examples.imports(e.pkg)} canvas={false} load={Island.Load.Click}>
					<button type="button" class="primary play-sound">Play the tone</button>
					<p class="note">Browsers start audio only after a click: the module is fetched and run then.</p>
				</Island.Wasm>;
			case JsIsland:
				<Counter.Island start={0}/>;
			case Module:
				<LabIsland.Lab wasm={Site.asset(e.wasm == null ? 'examples/${e.id}.wasm' : e.wasm)} imports={[Site.asset("web/imports.mjs")]}/>;
		}
	}

	// --- Home ---

	static function Home(props:{examples:Array<Example>}):View {
		var b = bench();
		var self = result(b, "self", "hxmc"), ref = result(b, "self", "reference");
		var cube = example(props.examples, "gfx-cube");
		var cubeSize = cube != null && cube.size != null ? kb(cube.size) : "about 200 KB";
		return <Page title="hxmc: Haxe's compiler in Haxe, compiled to machine code" section="Home"
			description="The Haxe compiler ported to Haxe, and hxmc, a Haxe target that writes machine code and WebAssembly itself, with packages for windows, graphics, text and UI in pure Haxe.">
			<header class="hero home">
				<div class="wrap">
					<h1>hxmc</h1>
					<p class="lead">The Haxe compiler ported to Haxe, compiled to machine code and WebAssembly by its own back end, with no C compiler, assembler or linker, and packages for windows, graphics, text and UI written in Haxe.</p>
					<div class="install">
						<Code lang="sh" code={"npm i -D @hxmc/cli\nnpx haxe -main Main --custom-target hxmc=app"}/>
					</div>
					<p class="cta"><a class="button primary" href={Site.link("examples.html")}>See the examples</a> <a class="button" href={Site.link("playground.html")}>Try the playground</a> <a class="button" href={Site.link("docs/using.html")}>Get started</a></p>
				</div>
			</header>
			<div class="wrap">
				<section class="tiles" aria-label="What it is">
					<article class="tile">
						<h2>A faithful compiler port</h2>
						<p>Every module of the OCaml compiler translated to Haxe, at the same path, in the same order. For the same arguments it writes the same output as the reference compiler, byte for byte.</p>
						<p class="proof"><b>279 / 279</b> HXB conformance cases, <b>66 / 66</b> macro cases, and every target's output identical (JS, Lua, Python, PHP, Neko, HashLink, JVM, C++, SWF).</p>
						<a href={Site.link("compiler.html")}>The compiler</a>
					</article>
					<article class="tile">
						<h2>Native code, no toolchain</h2>
						<p>hxmc writes x86-64 and ARM64 machine code and WebAssembly itself, links ELF, PE and Mach-O files itself, and cross-builds every target from one machine. It builds itself.</p>
						<p class="proof">{self == null || ref == null ? null : <span>The port compiles its own 52k lines in <b>{fixed(self.cpu_min, 1)} s</b> of CPU, the OCaml reference in {fixed(ref.cpu_min, 1)} s, with <b>{Math.round(100 - 100 * self.maxrss_mb / ref.maxrss_mb)}% less memory</b>.</span>}</p>
						<a href={Site.link("hxmc.html")}>How hxmc works</a>
					</article>
					<article class="tile with-demo">
						<h2>Pure-Haxe packages</h2>
						<p>Windows, input, audio, the GPU, fonts and a UI toolkit, calling the system's APIs directly: no C of our own. This cube is Haxe compiled to WebAssembly (drag it):</p>
						{cube == null ? null : <div class="tile-demo"><Demo e={cube}/></div>}
						<p class="proof"><b>{cubeSize}</b> of WebAssembly, drawing with WebGPU or WebGL2; the same program draws with Metal, Direct3D 11 and OpenGL.</p>
						<a href={Site.link("packages.html")}>The packages</a>
					</article>
				</section>
				<section class="onward" aria-label="Where next">
					<a class="card" href={Site.link("examples.html")}><b>Examples</b><span>live demos with their source</span></a>
					<a class="card" href={Site.link("playground.html")}><b>Playground</b><span>the compiler in your browser</span></a>
					<a class="card" href={Site.link("docs/index.html")}><b>Docs</b><span>guides, package READMEs, API</span></a>
					<a class="card" href={Site.link("compiler.html#download")}><b>Download</b><span>nightly builds for six platforms</span></a>
					<a class="card" href={Site.link("story.html")}><b>Story</b><span>how the port was made</span></a>
					<a class="card" href={Site.REPO}><b>Source</b><span>github.com/benmerckx/hxmc</span></a>
				</section>
			</div>
		</Page>;
	}

	// --- Compiler ---

	static function Compiler(props:{}):View {
		return <Page title="The compiler" section="Compiler" description="The Haxe compiler ported from OCaml to Haxe: conformance, downloads, benchmarks and the target generators.">
			<Hero kicker="The port" title="Haxe's compiler, in Haxe">
				<p class="lead">Each OCaml module of upstream's compiler translated to a Haxe module at the same path, keeping its functions, branches and data in the same order. hxmc compiles it to native binaries for Linux, macOS and Windows, and to WebAssembly for the playground.</p>
				<nav class="links">
					<a href="#status">Status</a><a href="#download">Download</a><a href="#benchmarks">Benchmarks</a><a href="#targets">Target generators</a><a href="#tools">lix</a>
				</nav>
			</Hero>
			<div class="wrap">
				<section id="status">
					<h2>Status</h2>
					<p>The port follows upstream (<code>haxe/src</code>, commit <code>fef2847</code>) module by module. For the same arguments it should produce the same output as the reference compiler; this is tested for:</p>
					<ul>
						<li>HXB output: 279 of 279 conformance cases (and the 7 the reference rejects), 66 of 66 macro cases;</li>
						<li>every target (JS, Lua, Python, PHP, Neko, HashLink, HL/C, JVM, C++, SWF) and <code>--xml</code>/<code>--json</code>, with a differential fuzzer and upstream test projects;</li>
						<li><code>--interp</code>, display requests, the compilation server and the Eval debugger;</li>
						<li>upstream's target-independent CI job (unit, misc, threads, tink_core, hxcoro), which passes with the native build.</li>
					</ul>
					<p class="note">Details: <a href={Site.link("docs/testing.html")}>docs/testing.md</a>. How it was done: <a href={Site.link("story.html")}>the story</a>.</p>
				</section>
				<section id="download">
					<h2>Download</h2>
					<p>Builds of the latest commit on <code>main</code>, with the standard library included:</p>
					<ul class="downloads">
						<li>Linux: <a href={NIGHTLY + "hxmc-haxe-linux-x86_64.tar.gz"}>x86-64</a>, <a href={NIGHTLY + "hxmc-haxe-linux-aarch64.tar.gz"}>ARM64</a></li>
						<li>macOS: <a href={NIGHTLY + "hxmc-haxe-macos-x86_64.tar.gz"}>x86-64</a>, <a href={NIGHTLY + "hxmc-haxe-macos-aarch64.tar.gz"}>ARM64</a></li>
						<li>Windows: <a href={NIGHTLY + "hxmc-haxe-windows-x86_64.zip"}>x86-64</a>, <a href={NIGHTLY + "hxmc-haxe-windows-aarch64.zip"}>ARM64</a></li>
					</ul>
					<Code lang="sh" code={"haxe -cp src --main Main --interp\nhaxe -cp src --main Main --js out.js"}/>
					<p class="note">It takes the same arguments as <code>haxe</code>. Every build is made by hxmc on Linux (machine code, its own linker, no C compiler for the port's code) and carries mbedtls and libuv, so <code>sys.ssl</code> and <code>eval.luv</code> work in macros and <code>--interp</code>. Set <code>HAXE_STD_PATH</code> to the <code>std</code> directory in the archive. macOS: a download from a browser is quarantined (<code>xattr -d com.apple.quarantine haxe</code>). All files: <a href="https://github.com/benmerckx/hxmc/releases/tag/nightly">nightly release</a>. With npm: <code>npm i -D @hxmc/cli</code> (<a href={Site.link("docs/using.html")}>docs/using.md</a>).</p>
				</section>
				<ScriptIsland name="tables" script="tables.js">
					<section id="benchmarks">
						<h2>Benchmarks</h2>
						<p>The port built by hxmc, as an x86-64 executable and as a WebAssembly module, compiling to HXB, against the OCaml reference. CPU time, best of 3, <code>-D disable-parallelism</code>; a run counts only if its output is identical to the reference's.</p>
						<div id="bench-results"><p class="note">Loading results…</p></div>
						<p class="note" id="bench-builds"></p>
						<p class="note" id="bench-machine"></p>
						<h3>Programs</h3>
						<p>The <a href="https://github.com/HaxeBenchmarks/benchmark-runner">HaxeBenchmarks</a> cases on hxmc (an x86-64 executable, a WebAssembly module under Node, and the WasmGC back end) and on the usual fast Haxe targets: C++ (hxcpp), the JVM, JavaScript on Node, HL/C and the HashLink JIT. Every Haxe compilation is ours: hxmc for its targets, the port, whose output for the others is byte-identical to the reference compiler's. Measured nightly on a GitHub Actions runner; each case's check program prints its results, compared across the targets.</p>
						<div id="programs-results"><p class="note">Loading results…</p></div>
						<div id="programs-compile"></div>
						<p class="note" id="programs-machine"></p>
						<p class="note" id="programs-noise"></p>
						<div id="programs-over-time" hidden>
							<h3>Over time</h3>
							<div id="programs-history"><p class="note">Loading history…</p></div>
						</div>
						<p class="note">Reproduce: <code>make bench</code> (<code>hxmc/test/Bench.hx</code>); the results of every run are on the <a href="https://github.com/benmerckx/hxmc/tree/bench-data">bench-data</a> branch.</p>
					</section>
					<section id="targets">
						<h2>Target generators</h2>
						<p>Compile time of the port built by hxmc (x86-64) against the reference for each target, on two projects. CPU time, best of 3; every output file identical (HL/C: once the few type names that digest the reference binary's own machine code are renamed on both sides). C++ and HL/C stop at the generated sources.</p>
						<div id="targets-results"><p class="note">Loading results…</p></div>
						<p class="note" id="targets-machine"></p>
					</section>
				</ScriptIsland>
				<section id="tools">
					<h2>lix</h2>
					<p><a href="https://github.com/lix-pm/lix.client">lix</a>, the Haxe package manager, and <a href="https://github.com/lix-pm/haxeshim">haxeshim</a>, ported from Haxe on Node.js and compiled by hxmc, one binary per platform (<span data-info="lixSize">about 2 MB</span>). It is <code>lix</code>, <code>haxe</code>, <code>haxelib</code> and <code>neko</code> in one file: it acts as the command it is named or linked as.</p>
					<ul class="downloads">
						<li>Linux: <a href={Site.link("tools/lix-linux-x86_64")}>x86-64</a>, <a href={Site.link("tools/lix-linux-arm64")}>ARM64</a></li>
						<li>macOS: <a href={Site.link("tools/lix-macos-x86_64")}>x86-64</a>, <a href={Site.link("tools/lix-macos-arm64")}>ARM64</a></li>
						<li>Windows: <a href={Site.link("tools/lix-windows-x86_64.exe")}>x86-64</a>, <a href={Site.link("tools/lix-windows-arm64.exe")}>ARM64</a></li>
					</ul>
					<p>Install it as <code>lix</code> in a directory on your <code>PATH</code> and let it create the <code>haxe</code>, <code>haxelib</code> and <code>neko</code> commands next to itself (<code>lix shims</code>). Linux (<code>lix-linux-arm64</code> on ARM64):</p>
					<Code lang="sh" code={"curl -fLo ~/bin/lix " + TOOLS + "lix-linux-x86_64 && chmod +x ~/bin/lix\nlix shims                       # symbolic links: ~/bin/haxe, ~/bin/haxelib, ~/bin/neko"}/>
					<p>macOS (<code>lix-macos-x86_64</code> on Intel):</p>
					<Code lang="sh" code={"curl -fLo ~/bin/lix " + TOOLS + "lix-macos-arm64 && chmod +x ~/bin/lix\nlix shims                       # symbolic links: ~/bin/haxe, ~/bin/haxelib, ~/bin/neko"}/>
					<p>Windows (PowerShell; <code>lix-windows-arm64.exe</code> on ARM64), e.g. into <code>C:\tools</code>, a directory on your <code>PATH</code>:</p>
					<Code lang="sh" code={"curl.exe -fLo C:\\tools\\lix.exe " + TOOLS + "lix-windows-x86_64.exe\nlix shims                       # hard links: haxe.exe, haxelib.exe, neko.exe"}/>
					<p>Then, in a project: <code>lix</code> downloads Haxe versions and libraries into the project's scope, and <code>haxe</code> runs the version and libraries of the scope it is called in, so editors and build scripts that call <code>haxe</code> get the right ones:</p>
					<Code lang="sh" code={"lix scope create                # a .haxerc for this directory\nlix install haxe 4.3.7          # download it and use it here\nlix +lib tink_core              # haxe_libraries/tink_core.hxml\nhaxe -lib tink_core --run Main  # runs Haxe 4.3.7 with tink_core\nlix use haxe 4.3.6              # switch to another downloaded version\nlix download                    # after a clone: the scope's Haxe and missing libraries"}/>
					<p class="note">The <code>haxe</code> shim adds about 2 ms to a compiler call (Node.js: about 60 ms). The compiler server modes (<code>--wait</code>, <code>--server-listen</code>, <code>--server-connect</code>) run on libuv with hxcoro coroutines. Compared with the npm package on 26 scenarios, output and installed files are identical. Details: <a href={Site.link("docs/using.html")}>docs/using.md</a>.</p>
				</section>
			</div>
		</Page>;
	}

	// --- hxmc ---

	static function Hxmc(props:{measured:Array<Measure.Measured>, examples:Array<Example>}):View {
		var pipeline = "typed AST --(ir.Lower)--> hxmc IR --(Prep)--> Mir (SSA) --(Inline, Sroa, Opt)-->\n    --(x64 | a64 Isel)--> LIR --(Regalloc, Emit)--> object (per module, cached)\n    --(wasm/WasmGen)--> wasm\n    --(Link: ELF | PE | Mach-O | wasm)--> executable";
		var interop = "import hxmc.unsafe.*;\n\n// a C function of a system library, called directly\n@:hxmc.lib(\"libc\") extern class C {\n\t@:hxmc.c(\"getpid\") static function getpid():Int;\n}\n\n// a C struct, as a value: on the stack, copied on assignment\n@:hxmc.struct class Point {\n\tpublic var x:Float32;\n\tpublic var y:Float32;\n}\n\nclass Main {\n\tstatic function main() {\n\t\tvar buf:Ptr<Float32> = Mem.alloc(4 * 1024);\n\t\tfor (i in 0...1024) buf[i] = i * 0.5;  // loads and stores, no bounds\n\t\ttrace(C.getpid(), buf[10]);\n\t}\n}";
		return <Page title="hxmc" section="hxmc" description="hxmc, a Haxe target that writes x86-64, ARM64 and WebAssembly itself: targets, sizes, build times, how it works, low-level Haxe and C interop.">
			<Hero kicker="The target" title="hxmc">
				<p class="lead">A Haxe target that turns the typed program into machine code and WebAssembly with its own code generator and linkers. No C compiler, assembler, system linker or SDK runs when a program is built, on any target, cross-compiling included.</p>
				<nav class="links"><a href="#targets">Targets</a><a href="#sizes">Sizes and build times</a><a href="#how">How it works</a><a href="#runtime">The runtime</a><a href="#interop">Low-level Haxe</a></nav>
			</Hero>
			<div class="wrap">
				<section id="targets">
					<h2>Targets</h2>
					<Code lang="hxml" code={"-cp src\n-main Main\n--custom-target hxmc=bin/app\n-D hxmc.target=windows-arm64   # any target, from any host"}/>
					<div class="table"><table>
						<thead><tr><th>Target</th><th>Output</th><th>Notes</th></tr></thead>
						<tbody>
							<tr><td><code>linux-x86_64</code>, <code>linux-arm64</code></td><td>static ELF (musl), or dynamic against glibc 2.17+</td><td><code>-D hxmc.libc=glibc</code> to load shared libraries (GPU drivers, GTK)</td></tr>
							<tr><td><code>macos-x86_64</code>, <code>macos-arm64</code></td><td>Mach-O, ad-hoc signed</td><td>the system's frameworks called through the Objective-C runtime</td></tr>
							<tr><td><code>windows-x86_64</code>, <code>windows-arm64</code></td><td>PE, imports written directly</td><td>no import libraries, no MSVC</td></tr>
							<tr><td><code>wasm32-wasi</code></td><td>a WebAssembly module</td><td>exception handling with <code>exnref</code>, or the legacy instructions (<code>-D hxmc.wasm-eh=legacy</code>); runs under node, wasmtime and in browsers</td></tr>
						</tbody>
					</table></div>
					<p>Threads, a precise generational collector, TLS (mbedtls) and libuv on every native target. Rebuilds compile only the modules that changed; typed modules are kept between builds.</p>
				</section>
				<section id="sizes">
					<h2>Sizes and build times</h2>
					{props.measured.length == 0 ? <p class="note">(Measured by the site build.)</p> : <MeasuredTable measured={props.measured}/>}
					<p class="note">Measured by this site's build on its machine: each program built alone with an empty cache (a cold build: the std and the packages compiled too); a rebuild after an edit compiles only the modules that changed. Sizes include the runtime, the collector and the C library (static musl on Linux, but for the glibc mode of the graphical programs).</p>
				</section>
				<section id="how">
					<h2>How it works</h2>
					<p>hxmc runs as the port's generate hook: the compiler types the program, and hxmc lowers each module to its IR, builds SSA, optimizes (inlining, scalar replacement of struct values, value numbering, store forwarding, loop-invariant code motion), selects instructions for x86-64 or ARM64, allocates registers with linear scan and encodes the machine code; or turns the same SSA into structured WebAssembly. Each module's object is cached; the linkers write the executable.</p>
					<Code lang="text" code={pipeline}/>
					<ul>
						<li>Program-wide numbers (type indices, field ids, offsets) are symbols the linker resolves, so a module's code does not change when the numbering does, and its cached object stays valid.</li>
						<li>Unwind tables for every target (<code>.eh_frame</code>, <code>.pdata</code>), frame pointers, and DWARF line tables with <code>-debug</code>: gdb, lldb and perf see Haxe functions and lines.</li>
						<li>hxmc builds itself: a committed WebAssembly stage0 under node builds the first native tool, which rebuilds itself byte-identically.</li>
					</ul>
					<p class="note">Details: <a href={Site.link("docs/hxmc.html")}>docs/hxmc.md</a>.</p>
				</section>
				<section id="runtime">
					<h2>The runtime, in Haxe</h2>
					<p>Most of the runtime is Haxe compiled with the program: strings, Dynamic access, reflection, arrays, dates, inflate, the POSIX and Windows system layers, and Math (musl's libm ported, with the same results on every target). The collector, threads and the stop-the-world handshake, startup and exceptions are Haxe too: no C of hxmc's own is linked, only the C library, mbedtls and libuv.</p>
					<p>The collector is precise and generational: a nursery per thread that adapts its size to what survives, a mark-sweep old space, shadow stacks for references live across a call.</p>
				</section>
				<section id="interop">
					<h2>Low-level Haxe and C interop</h2>
					<p>The runtime and the packages are written with a small low-level layer (<code>hxmc.unsafe</code>): raw pointers and memory, struct values with C's layout, externs of C functions in the system's libraries, callbacks C calls, thread-locals. The packages use it to call X11, Cocoa, Win32, OpenGL, Metal, Direct3D and the browser directly.</p>
					<Code code={interop}/>
					<p class="note">The design, built in part: <a href={Site.link("docs/plans/lowlevel.html")}>docs/plans/lowlevel.md</a>.</p>
				</section>
			</div>
		</Page>;
	}

	static function MeasuredTable(props:{measured:Array<Measure.Measured>}):View {
		var programs = [for (p in Measure.PROGRAMS) p.name];
		function cell(t:String, p:String):View {
			var m = Lambda.find(props.measured, m -> m.target == t && m.program == p);
			return m == null ? <td class="num">–</td> : <td class="num"><b>{kb(m.size)}</b><span class="sub">{fixed(m.seconds, 1)} s</span></td>;
		}
		return <div class="table"><table class="measured">
			<thead><tr><th>Target</th>{[for (p in Measure.PROGRAMS) <th class="num" title={p.note}>{p.name}</th>]}</tr></thead>
			<tbody>{[
				for (t in Measure.TARGETS)
					<tr><td><code>{t}</code></td>{[for (p in programs) cell(t, p)]}</tr>
			]}</tbody>
		</table></div>;
	}

	// --- Packages ---

	public static final PACKAGES = [
		["os", "@hxmc/os", "Windows, input, the app loop and audio: X11, Cocoa, Win32 and the browser's canvas; ALSA, Core Audio, WASAPI and WebAudio."],
		["gfx", "@hxmc/gfx", "A portable GPU API shaped like WebGPU, with back ends for OpenGL and GLES, Metal, Direct3D 11, WebGPU and WebGL2, and shaders written in Haxe."],
		["text", "@hxmc/text", "TrueType fonts in pure Haxe: parsing, an anti-aliased rasterizer, shaping with kerning and fallback fonts, bidi and Arabic, line layout, a glyph atlas."],
		["view", "@hxmc/view", "Signals and JSX-like markup on every target: fine-grained reactivity, markup compiled to direct calls on a renderer chosen at compile time."],
		["ui", "@hxmc/ui", "A UI toolkit: flexbox layout checked against Chromium's, events and focus, widgets, drawn on the GPU or as the platform's own controls."],
		["web", "@hxmc/web", "@hxmc/view on the web: a DOM renderer, static pages rendered at build time, hydration, islands in JavaScript or WebAssembly. This site is built with it."],
	];

	// the first ```haxe block of a README (after a heading, when given)
	static function sample(readme:String, ?after:String):Null<String> {
		var text = Site.read(readme);
		if (after != null) {
			var at = text.indexOf(after);
			if (at < 0) return null;
			text = text.substr(at);
		}
		var start = text.indexOf("```haxe\n");
		if (start < 0) return null;
		var end = text.indexOf("\n```", start + 8);
		var code = text.substring(start + 8, end);
		var lines = code.split("\n");
		return lines.length > 26 ? lines.slice(0, 25).join("\n") + "\n// ..." : code;
	}

	static function Packages(props:{examples:Array<Example>}):View {
		return <Page title="Packages" section="Packages" description="The hxmc packages, in pure Haxe: os, gfx, text, view, ui and web.">
			<Hero kicker="Pure Haxe" title="Packages">
				<p class="lead">Libraries in Haxe that call the system's APIs directly, with no C of their own; each on npm, found by <code>-lib</code>. They run natively on every desktop target and in the browser as WebAssembly (web: as JavaScript too).</p>
				<nav class="links">{[for (p in PACKAGES) <a href={"#" + p[0]}>{p[0]}</a>]}</nav>
			</Hero>
			<div class="wrap">{[
				for (p in PACKAGES) {
					var readme = 'packages/${p[0]}/README.md';
					var code = sample(readme);
					var audio = p[0] == "os" ? sample(readme, "## Audio") : null;
					var exs = props.examples.filter(e -> e.pkg == p[0]);
					<section class="package" id={p[0]}>
						<div class="package-text">
							<h2>{p[1]}</h2>
							<p>{p[2]}</p>
							<Code lang="sh" code={'npm i -D ${p[1]}    # then -lib hxmc.${p[0]}'}/>
							<p class="links">
								<a href={Site.link('docs/packages/${p[0]}.html')}>README</a>
								<a href={Site.link('docs/api/${p[0]}.html')}>API</a>
								{p[0] == "ui" ? <a href={Site.link("docs/packages/ui-guide.html")}>Guide</a> : null}
								<a href={Site.github('packages/${p[0]}')}>Source</a>
							</p>
							{exs.length == 0 ? null : <p class="note">Examples: {[for (k in 0...exs.length) <span>{k > 0 ? ", " : ""}<a href={Site.link("examples.html#" + exs[k].id)}>{exs[k].title}</a></span>]}</p>}
						</div>
						<div class="package-code">
							{code == null ? null : <Code code={code}/>}
							{audio == null ? null : <Code code={audio}/>}
						</div>
					</section>;
				}
			]}</div>
		</Page>;
	}

	// --- Examples ---

	static function ExamplesPage(props:{examples:Array<Example>}):View {
		var order = ["gfx", "ui", "text", "os", "view", "web"];
		var sorted = props.examples.copy();
		sorted.sort((a, b) -> order.indexOf(a.pkg) - order.indexOf(b.pkg));
		return <Page title="Examples" section="Examples" description="Live examples of the hxmc packages, each running in the page as WebAssembly or JavaScript next to its source.">
			<Hero kicker="Live" title="Examples">
				<p class="lead">Each example is a program from a package's <code>examples/</code> folder, built by this site's build for the browser and running here, next to its source. The same source builds a native program for Linux, macOS and Windows.</p>
				<nav class="links">{[for (e in sorted) <a href={"#" + e.id}>{e.title}</a>]}</nav>
			</Hero>
			<div class="wrap gallery">{[for (e in sorted) <ExampleCard e={e}/>]}</div>
		</Page>;
	}

	static function ExampleCard(props:{e:Example}):View {
		var e = props.e;
		var labels = [for (s in e.sources) haxe.io.Path.withoutDirectory(s)];
		var size = e.size == null ? null : kb(e.size) + " of WebAssembly";
		var kind = switch e.demo {
			case Canvas(_, _): "wide";
			case _: "narrow";
		}
		return <article class={"example " + kind} id={e.id}>
			<header class="example-head">
				<h2><a href={"#" + e.id}>{e.title}</a></h2>
				<p>{e.summary}</p>
				<p class="tags">{[for (t in e.tags) <span class="tag">{t}</span>]}{size == null ? null : <span class="size">{size}</span>}</p>
			</header>
			<div class="example-body">
				<div class="example-demo"><Demo e={e}/></div>
				<div class="example-source">
					{labels.length > 1 ? <SiteIslands.Tabs id={"src-" + e.id} labels={labels}/> : <div class="tabs single"><span>{labels[0]}</span></div>}
					{[
						for (k in 0...e.sources.length)
							<div class="file" id={"src-" + e.id + "-" + k} hidden={k > 0}>
								<Raw html={Highlight.block(Site.read(e.sources[k]), "haxe")}/>
							</div>
					]}
					<p class="note"><a href={Site.github(e.file)}>{e.file}</a> · <code>-main {e.main}</code></p>
				</div>
			</div>
		</article>;
	}

	// --- Playground ---

	static function Playground(props:{}):View {
		return <Page title="Playground" section="Playground" description="The Haxe compiler, ported to Haxe and compiled to WebAssembly by hxmc, running in your browser: --interp and HXB, with completion and diagnostics."
			bodyClass="playground-page">
			<div class="wrap">
				<ScriptIsland name="playground" script="playground.js">
					<section id="playground">
						<h1>Playground</h1>
						<p><em>Run</em> type-checks and runs the program with <code>--interp</code>. <em>Compile to HXB</em> writes an HXB archive. The compiler runs here as WebAssembly with exception handling: with <code>exnref</code> where the browser has it, else with the legacy instructions (Chrome and Edge 95+, Firefox 100+, Safari 15.2+).</p>
						<div class="toolbar">
							<label>Example <select id="example"></select></label>
							<button id="run" class="primary" disabled>Run</button>
							<button id="hxb" disabled>Compile to HXB</button>
							<span id="state" class="state">Loading compiler…</span>
						</div>
						<div class="play">
							<div id="editor" aria-label="Haxe source"></div>
							<div class="output">
								<div class="outhead">Output <span id="timing"></span></div>
								<pre id="out"></pre>
								<div id="members" hidden></div>
							</div>
						</div>
						<p class="note">Completion, hover and diagnostics come from the same compiler. Download: <span data-info="wasmGz">about 2 MB</span> of WebAssembly, <span data-info="dataGz">about 0.2 MB</span> of standard library. Some examples are from <a href="https://try.haxe.org/">try.haxe.org</a> (<a href={Site.link("playground/LICENSE-try-haxe.txt")}>MIT</a>).</p>
					</section>
				</ScriptIsland>
			</div>
		</Page>;
	}

	// --- Story ---

	static function Story(props:{}):View {
		return <Page title="Story" section="Story" description="How the Haxe compiler was ported from OCaml to Haxe and given its own machine-code back end.">
			<Hero kicker="History" title="The story"/>
			<div class="wrap"><Raw cls="story" html={Site.read("site/content/story.html")} tag="section"/></div>
		</Page>;
	}
}
