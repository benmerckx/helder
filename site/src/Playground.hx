// Playground UI. The compiler runs in Web Workers (worker.js): one for Run /
// Compile to HXB, one for the editor's display requests (completion, hover,
// signature help, diagnostics), so typing never waits behind a running program.
import js.Browser.document;
import js.Browser.window;
import js.Syntax;
import js.html.ButtonElement;
import js.html.Element;
import js.html.SelectElement;
import js.html.TextAreaElement;
import js.lib.Object;
import js.lib.Promise;
import js.lib.RegExp;

typedef Program = {main:String, file:String, code:String};

class Playground {
	static inline final MONACO = "https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs";

	static var out:Element;
	static var state:Element;
	static var timing:Element;
	static var members:Element;
	static var runBtn:ButtonElement;
	static var hxbBtn:ButtonElement;
	static var example:SelectElement;

	static function main() {
		out = byId("out");
		state = byId("state");
		timing = byId("timing");
		members = byId("members");
		runBtn = cast byId("run");
		hxbBtn = cast byId("hxb");
		example = cast byId("example");

		try {
			saved = window.localStorage.getItem("hih-code");
		} catch (e:Dynamic) {}

		window.fetch("examples/index.json").then((r) -> r.json()).then((list:Array<Dynamic>) -> {
			examples = list;
			final groups:haxe.DynamicAccess<Element> = {};
			for (i in 0...list.length) {
				final ex = list[i];
				final label = ex.source == "try.haxe.org" ? "From try.haxe.org" : "haxe-in-haxe";
				if (!Js.truthy(groups[label])) {
					final group:js.html.OptGroupElement = cast document.createElement("optgroup");
					group.label = label;
					groups[label] = cast example.appendChild(group);
				}
				groups[label].appendChild(Syntax.construct("Option", ex.title, i));
			}
			if (!Js.truthy(saved)) loadExample(0);
		});
		example.addEventListener("change", () -> loadExample(Std.parseInt(example.value)));

		final loader:js.html.ScriptElement = cast document.createElement("script");
		loader.src = MONACO + "/loader.js";
		loader.onerror = fallbackEditor;
		loader.onload = () -> {
			js.Lib.global.MonacoEnvironment = {
				getWorkerUrl: () -> "data:text/javascript;charset=utf-8,"
					+ StringTools.urlEncode('self.MonacoEnvironment = {baseUrl: "${MONACO}/../"}; importScripts("${MONACO}/base/worker/workerMain.js");')
			};
			final require:Dynamic = Syntax.code("require");
			require.config({paths: {vs: MONACO}});
			require(["vs/editor/editor.main"], setupMonaco, fallbackEditor);
		};
		document.head.appendChild(loader);

		LOW_MEMORY = {
			final dm:Null<Float> = (cast window.navigator).deviceMemory;
			Js.or(dm, 8) <= 4 || window.matchMedia("(pointer: coarse)").matches;
		};
		MEMORY64 = {
			// a module with one memory64 memory (limits flag 4)
			try {
				js.lib.WebAssembly.validate(new js.lib.Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 4, 0]));
			} catch (err:Dynamic) {
				false;
			}
		};

		if (!MEMORY64) setBusy(true, "This browser cannot run the compiler: it needs WebAssembly with 64-bit memory (Chrome or Edge 133+, Firefox 134+).");
		else {
			setBusy(true, "The compiler loads when the playground is in view…");
			final playground = document.getElementById("playground");
			if (playground != null && Syntax.code("\"IntersectionObserver\" in self")) {
				var io:js.html.IntersectionObserver = null;
				io = new js.html.IntersectionObserver((entries, _) -> {
					if (entries.filter((x) -> x.isIntersecting).length > 0) {
						io.disconnect();
						setBusy(true, "Loading compiler…");
						ensureRunner();
					}
				});
				io.observe(playground);
			} else {
				setBusy(true, "Loading compiler…");
				ensureRunner();
			}
		}

		runBtn.onclick = () -> start("run");
		hxbBtn.onclick = () -> start("hxb");

		pending = new js.lib.Map();
		queue = new js.lib.Map();
		encoder = new js.html.TextEncoder();

		// build facts (sizes, date, commit) from build-info.json, written by site/build.sh
		window.fetch("build-info.json").then((r) -> r.ok ? r.json() : null).then((info:Dynamic) -> {
			if (!Js.truthy(info)) return;
			final els = document.querySelectorAll("[data-info]");
			for (k in 0...els.length) {
				final el:Element = cast els[k];
				final v = (info : haxe.DynamicAccess<Dynamic>)[el.dataset.info];
				if (v != null) el.textContent = v;
			}
		}).catchError((_) -> {});
	}

	static inline function byId(id:String):Element {
		return document.getElementById(id);
	}

	// ---- the program: Main.hx / Test.hx, main class detected from the source

	static function mainOf(code:String):String {
		// the class declaring `static function main`: the nearest class before it
		final m = new RegExp("\\b(?:static\\s+(?:public\\s+|private\\s+)?|(?:public|private)\\s+static\\s+)function\\s+main\\s*\\(").exec(code);
		if (m != null) {
			var name:String = null;
			final re = new RegExp("\\bclass\\s+([A-Z]\\w*)", "g");
			final before = code.substring(0, m.index);
			var c;
			while ((c = re.exec(before)) != null) name = c[1];
			if (Js.truthy(name)) return name;
		}
		return new RegExp("^\\s*function\\s+main\\s*\\(", "m").test(code) ? "Test" : "Main"; // module-level main
	}

	static function program(code:String):Program {
		final main = mainOf(code);
		return {main: main, file: main + ".hx", code: code};
	}

	// ---- editor: Monaco when it loads, a textarea otherwise

	static var editor:Dynamic = null;
	static var textarea:TextAreaElement = null;
	static var early = ""; // `early`: code set before an editor exists

	static function getCode():String {
		return editor != null ? editor.getValue() : textarea != null ? textarea.value : early;
	}

	static function setCode(c:String) {
		if (editor != null) editor.setValue(c); else if (textarea != null) textarea.value = c; else early = c;
	}

	static var saved:String = null;

	static function save() {
		try {
			window.localStorage.setItem("hih-code", getCode());
		} catch (e:Dynamic) {}
	}

	static var examples:Array<Dynamic> = [];

	static function loadExample(i:Int) {
		window.fetch("examples/" + (examples[i].file : String)).then((r) -> r.text()).then((c) -> {
			setCode(c);
			save();
		});
	}

	static function fallbackEditor() {
		textarea = cast document.createElement("textarea");
		textarea.spellcheck = false;
		textarea.wrap = "off";
		textarea.setAttribute("aria-label", "Haxe source");
		textarea.value = Js.or(saved, early);
		textarea.addEventListener("input", save);
		textarea.addEventListener("keydown", (e:js.html.KeyboardEvent) -> {
			if (e.key == "Tab") {
				e.preventDefault();
				textarea.setRangeText("\t", textarea.selectionStart, textarea.selectionEnd, END);
				save();
			} else if (e.key == "Enter" && (e.ctrlKey || e.metaKey)) {
				e.preventDefault();
				start("run");
			}
		});
		byId("editor").replaceWith(textarea);
	}

	static function setupMonaco() {
		final monaco:Dynamic = js.Lib.global.monaco;
		defineHaxe();
		final dark = window.matchMedia("(prefers-color-scheme: dark)");
		editor = monaco.editor.create(byId("editor"), {
			value: Js.or(saved, early),
			language: "haxe",
			theme: dark.matches ? "vs-dark" : "vs",
			automaticLayout: true,
			minimap: {enabled: false},
			fontSize: 14,
			tabSize: 4,
			insertSpaces: false,
			scrollBeyondLastLine: false,
			fixedOverflowWidgets: true,
		});
		dark.addEventListener("change", () -> monaco.editor.setTheme(dark.matches ? "vs-dark" : "vs"));
		editor.onDidChangeModelContent(() -> {
			save();
			scheduleCheck();
		});
		editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () -> start("run"));
		registerProviders();
		scheduleCheck();
	}

	// ---- running programs

	// The compiler is a 10 MB WebAssembly module with 64-bit memory. It is compiled
	// once, only when the playground comes into view (or Run is pressed), and the
	// compiled module is shared with the workers. Phones and low-memory devices
	// skip the background type-checker (diagnostics, completion), the second
	// compiler instance: two of them got mobile browsers' tabs killed.
	static var LOW_MEMORY:Bool;
	static var MEMORY64:Bool;
	static var wasmModule:Promise<Dynamic> = null;

	static function compilerModule():Promise<Dynamic> {
		if (wasmModule == null) wasmModule = js.lib.WebAssembly.compileStreaming(cast window.fetch("hih.wasm"));
		return wasmModule;
	}

	static function startWorker(onmessage:js.html.MessageEvent->Void):js.html.Worker {
		final w = new js.html.Worker("worker.js");
		w.onmessage = onmessage;
		compilerModule().then((module) -> w.postMessage({type: "module", module: module}), (err:Dynamic) -> {
			setBusy(true, "The compiler could not be loaded: " + Js.str(Js.truthy(err) && Js.truthy(err.message) ? err.message : err));
		});
		return w;
	}

	static var runner:js.html.Worker = null;
	static var busy = false;
	static var zipUrl:String = null;
	static var runnerReady = false;

	static function newRunner() {
		runner = startWorker((e) -> onRunnerMessage(e.data));
		runner.postMessage({type: "warmup"});
	}

	static function ensureRunner() {
		if (runner != null || !MEMORY64) return;
		newRunner();
	}

	static function setBusy(b:Bool, ?text:String) {
		busy = b;
		runBtn.disabled = hxbBtn.disabled = b;
		state.textContent = Js.or(text, "");
	}

	static function print(text:String, ?cls:String) {
		final span = document.createSpanElement();
		if (Js.truthy(cls)) span.className = cls;
		span.textContent = text + "\n";
		out.appendChild(span);
	}

	static function start(mode:String) {
		if (busy) return;
		out.textContent = "";
		members.hidden = true;
		members.textContent = "";
		timing.textContent = "";
		setBusy(true, mode == "run" ? "Compiling and running…" : "Compiling to HXB…");
		final p = program(getCode());
		runner.postMessage({type: "compile", mode: mode, main: p.main, file: p.file, code: p.code});
	}

	static function onRunnerMessage(m:Dynamic) {
		switch (m.type) {
			case "ready":
				runnerReady = true;
				setBusy(false, "Ready. Ctrl+Enter runs.");
				scheduleCheck();
			case "out":
				print(m.text);
			case "err":
				print(m.text, "err");
			case "done":
				timing.textContent = 'exit ${Js.str(m.status)}, ${Js.fixed(m.ms, 0)} ms';
				if (Js.truthy(m.zip)) showZip(m.zip);
				setBusy(false, "");
			case "failed":
				print(m.message, "err");
				runner.terminate(); // a crashed instance (stack or memory exhausted): start over
				newRunner();
				setBusy(true, "Restarting compiler…");
		}
	}

	// the members of the HXB archive, from the ZIP central directory
	static function showZip(buf:js.lib.ArrayBuffer) {
		final bytes = new js.lib.Uint8Array(buf), view = new js.lib.DataView(buf);
		var eocd = -1;
		var i = bytes.length - 22;
		while (i >= 0) {
			if (view.getUint32(i, true) == 0x06054b50) {
				eocd = i;
				break;
			}
			i--;
		}
		if (eocd < 0) return;
		final count = view.getUint16(eocd + 10, true);
		var p = view.getUint32(eocd + 16, true);
		final rows:Array<{name:String, size:Int}> = [];
		var total = 0;
		for (_ in 0...count) {
			final size = view.getUint32(p + 24, true), nlen = view.getUint16(p + 28, true);
			final elen = view.getUint16(p + 30, true), clen = view.getUint16(p + 32, true);
			rows.push({name: new js.html.TextDecoder().decode(bytes.subarray(p + 46, p + 46 + nlen)), size: size});
			total += size;
			p += 46 + nlen + elen + clen;
		}
		if (Js.truthy(zipUrl)) js.html.URL.revokeObjectURL(zipUrl);
		zipUrl = js.html.URL.createObjectURL(new js.html.Blob([buf], {type: "application/zip"}));
		print('${count} HXB modules, ${Js.locale(total)} bytes uncompressed.');
		final a = document.createAnchorElement();
		a.href = zipUrl;
		a.download = "out.hxb.zip";
		a.textContent = "Download the archive";
		final table = document.createTableElement();
		table.innerHTML = "<thead><tr><th>module</th><th>bytes</th></tr></thead>";
		final tb = document.createElement("tbody");
		rows.sort((x, y) -> (x.name : Dynamic).localeCompare(y.name));
		for (row in rows) {
			final tr = document.createTableRowElement();
			tr.innerHTML = "<td></td><td></td>";
			tr.children[0].textContent = row.name;
			tr.children[1].textContent = Js.locale(row.size);
			tb.appendChild(tr);
		}
		table.appendChild(tb);
		members.append(a, table);
		members.hidden = false;
	}

	// ---- display requests (JSON-RPC, as an IDE sends them), on their own worker

	static var lsp:js.html.Worker = null;
	static var lspSeq = 0;
	static var pending:js.lib.Map<Int, Dynamic->Void>;

	static function newLsp() {
		lsp = startWorker((e) -> {
			final m:Dynamic = e.data, p = pending.get(m.id);
			if (p == null) return;
			pending.delete(m.id);
			if (m.type == "failed") {
				lsp.terminate();
				newLsp();
				p(null);
			} else p(m);
		});
	}

	// one request at a time; a newer request of the same kind replaces a queued one
	static var queue:js.lib.Map<String, {msg:Dynamic, resolve:Dynamic->Void}>;
	static var inflight = false;

	static function request(kind:String, msg:Dynamic):Promise<Dynamic> {
		// the type-checker starts once the compiler has loaded, and not on small devices
		if (LOW_MEMORY || !MEMORY64 || !runnerReady) return Promise.resolve(null);
		if (lsp == null) newLsp();
		return new Promise((resolve, _) -> {
			final prev = queue.get(kind);
			if (prev != null) prev.resolve(null);
			queue.set(kind, {msg: msg, resolve: resolve});
			pump();
		});
	}

	static function pump() {
		if (inflight || queue.size == 0) return;
		final kind = queue.keys().next().value;
		final q = queue.get(kind);
		queue.delete(kind);
		inflight = true;
		final id = ++lspSeq;
		pending.set(id, (m) -> {
			inflight = false;
			q.resolve(m);
			pump();
		});
		lsp.postMessage(Object.assign({}, q.msg, {id: id}));
	}

	static var encoder:js.html.TextEncoder;

	static function byteOffset(model:Dynamic, position:Dynamic):Int {
		return encoder.encode((model.getValue() : String).substring(0, model.getOffsetAt(position))).length;
	}

	static function display(method:String, model:Dynamic, position:Dynamic, ?extra:Dynamic):Promise<Dynamic> {
		final p = program(model.getValue());
		final params = Object.assign({file: "/work/" + p.file, offset: byteOffset(model, position)}, extra);
		return request(method, {type: "display", main: p.main, file: p.file, code: p.code, request: {jsonrpc: "2.0", id: 1, method: method, params: params}}).then((m:Dynamic) -> {
			if (!Js.truthy(m)) return null;
			final line = (m.output : String).split("\n").filter((l) -> StringTools.startsWith(l, '{"jsonrpc"'))[0];
			if (!Js.truthy(line)) return null;
			try {
				final r:Dynamic = haxe.Json.parse(line);
				return Js.truthy(r.result) ? r.result.result : null;
			} catch (e:Dynamic) {
				return null;
			}
		});
	}

	// Haxe's JSON types (haxe.display.JsonModuleTypes) as Haxe source
	static function typeStr(t:Dynamic):String {
		if (!Js.truthy(t)) return "?";
		final a:Dynamic = t.args;
		final path = (p:Dynamic) -> (p.typeName : String);
		final params = (ps:Array<Dynamic>) -> Js.truthy(ps) && ps.length > 0 ? "<" + ps.map(typeStr).join(", ") + ">" : "";
		return switch (t.kind : String) {
			case "TMono": "Unknown";
			case "TInst" | "TEnum" | "TType" | "TAbstract": path(a.path) + params(a.params);
			case "TFun": "(" + (a.args : Array<Dynamic>).map((x) -> (Js.truthy(x.opt) ? "?" : "") + (Js.truthy(x.name) ? (x.name : String) + ":" : "") + typeStr(x.t)).join(", ") + ") -> " + typeStr(a.ret);
			case "TAnonymous": "{ " + (Js.or(a.fields, []) : Array<Dynamic>).map((f) -> (f.name : String) + ":" + typeStr(f.type)).join(", ") + " }";
			case "TDynamic": Js.truthy(a) ? "Dynamic<" + typeStr(a) + ">" : "Dynamic";
			default: t.kind;
		}
	}

	static function itemInfo(item:Dynamic):Dynamic {
		final a:Dynamic = Js.or(item.args, {});
		final f:Dynamic = a.field;
		final K:Dynamic = js.Lib.global.monaco.languages.CompletionItemKind;
		return switch (item.kind : String) {
			case "ClassField" | "EnumAbstractField" | "AnonField":
				{label: f.name, kind: Js.truthy(f.kind) && f.kind.kind == "FMethod" ? K.Method : K.Field, detail: typeStr(f.type), doc: f.doc};
			case "EnumField": {label: a.field.name, kind: K.EnumMember, detail: typeStr(a.field.type), doc: a.field.doc};
			case "Local": {label: a.name, kind: K.Variable, detail: typeStr(a.type)};
			case "Type": {label: a.path.typeName, kind: a.kind == "Interface" ? K.Interface : a.kind == "Enum" ? K.Enum : K.Class, detail: (Js.or(a.path.pack, []) : Array<String>).concat([a.path.typeName]).join("."), doc: a.doc};
			case "Package": {label: Js.truthy(a.path) && Js.truthy(a.path.pack) ? a.path.pack[(a.path.pack.length : Int) - 1] : Js.str(a), kind: K.Module};
			case "Module": {label: Js.truthy(a.path) ? a.path.moduleName : Js.str(a), kind: K.Module};
			case "Keyword": {label: a.name, kind: K.Keyword};
			case "Literal": {label: a.name, kind: K.Value, detail: typeStr(a.type)};
			case "Metadata": {label: a.name, kind: K.Property, doc: a.doc};
			case "TypeParameter": {label: a.name, kind: K.TypeParameter};
			default: {label: Js.or(Js.or(Js.truthy(f) ? f.name : f, a.name), item.kind), kind: K.Text};
		}
	}

	static function registerProviders() {
		final monaco:Dynamic = js.Lib.global.monaco;
		monaco.languages.registerCompletionItemProvider("haxe", {
			triggerCharacters: [".", ":", " "],
			provideCompletionItems: (model:Dynamic, position:Dynamic, context:Dynamic) -> {
				final ch:String = context.triggerCharacter;
				if (ch == " ") { // only after `new`, `extends`, `implements`, `import`, `using`, `case`
					final before = (model.getLineContent(position.lineNumber) : String).substring(0, (position.column : Int) - 1);
					if (!new RegExp("\\b(new|extends|implements|import|using|case|cast)\\s$").test(before)) return Promise.resolve({suggestions: []});
				}
				return display("display/completion", model, position, {wasAutoTriggered: Js.truthy(ch)}).then((r:Dynamic) -> {
					if (!Js.truthy(r) || !Js.truthy(r.items)) return {suggestions: []};
					final word = model.getWordUntilPosition(position);
					final range = Syntax.construct(monaco.Range, position.lineNumber, word.startColumn, position.lineNumber, word.endColumn);
					final seen = new js.lib.Set<String>();
					final suggestions:Array<Dynamic> = [];
					for (item in (r.items : Array<Dynamic>)) {
						final i = itemInfo(item);
						if (!Js.truthy(i.label) || seen.has(Js.str(i.label) + Js.str(i.kind))) continue;
						seen.add(Js.str(i.label) + Js.str(i.kind));
						suggestions.push({
							label: i.label,
							kind: i.kind,
							detail: i.detail,
							documentation: Js.truthy(i.doc) ? {value: i.doc.trim()} : js.Lib.undefined,
							insertText: i.label,
							range: range,
							sortText: StringTools.lpad(Js.str(suggestions.length), "0", 5)
						});
					}
					return {suggestions: suggestions};
				});
			},
		});
		monaco.languages.registerHoverProvider("haxe", {
			provideHover: (model:Dynamic, position:Dynamic) -> display("display/hover", model, position).then((r:Dynamic) -> {
				if (!Js.truthy(r) || !Js.truthy(r.item)) return null;
				final t:Dynamic = Js.truthy(r.item.type) ? typeStr(r.item.type) : itemInfo(r.item).detail;
				final doc:String = Js.or(Js.truthy(r.item.args) ? Js.or(r.item.args.doc, Js.truthy(r.item.args.field) ? r.item.args.field.doc : r.item.args.field) : r.item.args, "");
				final contents:Array<Dynamic> = [{value: "```haxe\n" + Js.str(Js.or(t, r.item.kind)) + "\n```"}];
				if (Js.truthy(doc)) contents.push({value: (doc : Dynamic).trim()});
				return {contents: contents};
			}),
		});
		monaco.languages.registerSignatureHelpProvider("haxe", {
			signatureHelpTriggerCharacters: ["(", ","],
			provideSignatureHelp: (model:Dynamic, position:Dynamic) -> display("display/signatureHelp", model, position, {wasAutoTriggered: true}).then((r:Dynamic) -> {
				if (!Js.truthy(r) || !Js.truthy(r.signatures) || r.signatures.length == 0) return null;
				return {
					value: {
						activeSignature: Js.or(r.activeSignature, 0),
						activeParameter: Js.or(r.activeParameter, 0),
						signatures: (r.signatures : Array<Dynamic>).map((s:Dynamic) -> {
							final ps = (s.args : Array<Dynamic>).map((x) -> (Js.truthy(x.opt) ? "?" : "") + (x.name : String) + ":" + typeStr(x.t));
							return {label: "(" + ps.join(", ") + ") -> " + typeStr(s.ret), documentation: Js.or(s.documentation, ""), parameters: ps.map((label) -> {label: label})};
						}),
					},
					dispose: () -> {},
				};
			}),
		});
		monaco.languages.registerDefinitionProvider("haxe", {
			provideDefinition: (model:Dynamic, position:Dynamic) -> display("display/definition", model, position).then((r:Dynamic) -> {
				if (!Js.truthy(r) || r.length == 0) return null;
				return (r : Array<Dynamic>).filter((d) -> StringTools.startsWith(d.file, "/work/")).map((d) -> {
					uri: model.uri,
					range: Syntax.construct(monaco.Range, d.range.start.line + 1, d.range.start.character + 1, d.range.end.line + 1, d.range.end.character + 1),
				});
			}),
		});
	}

	// diagnostics: type-check after typing stops, errors as editor markers
	static var checkTimer = 0;

	static function scheduleCheck() {
		window.clearTimeout(checkTimer);
		// right after a `.` (completion territory) the line is usually incomplete:
		// wait longer before reporting it as an error
		var delay = 700;
		final pos:Dynamic = Js.truthy(editor) ? editor.getPosition() : editor;
		if (Js.truthy(pos)) {
			final before = (editor.getModel().getLineContent(pos.lineNumber) : String).substring(0, (pos.column : Int) - 1);
			if (new RegExp("\\.\\w*$").test(before)) delay = 2500;
		}
		checkTimer = window.setTimeout(check, delay);
	}

	static function check() {
		if (!Js.truthy(editor)) return;
		final monaco:Dynamic = js.Lib.global.monaco;
		final model:Dynamic = editor.getModel();
		final p = program(model.getValue());
		request("check", {type: "check", main: p.main, file: p.file, code: p.code}).then((m:Dynamic) -> {
			if (!Js.truthy(m) || model.getValue() != p.code) return;
			final markers:Array<Dynamic> = [];
			// classic message format: File.hx:LINE: characters A-B : message (or lines A-B)
			final re = new RegExp("^(?:\\/work\\/)?([\\w.]+\\.hx):(\\d+): (characters|lines) (\\d+)-(\\d+) : (.*)$");
			for (l in (m.output : String).split("\n")) {
				final x = re.exec(l);
				if (x == null || x[1] != p.file) continue;
				final line = Std.parseInt(x[2]), a = Std.parseInt(x[4]), b = Std.parseInt(x[5]);
				final warning = new RegExp("^Warning ?:").test(x[6]);
				markers.push(x[3] == "characters"
					? {startLineNumber: line, startColumn: a + 1, endLineNumber: line, endColumn: Math.max(b + 1, a + 2), message: x[6], severity: warning ? monaco.MarkerSeverity.Warning : monaco.MarkerSeverity.Error}
					: {startLineNumber: a, startColumn: 1, endLineNumber: b, endColumn: 1000, message: x[6], severity: monaco.MarkerSeverity.Error});
			}
			monaco.editor.setModelMarkers(model, "haxe", markers);
		});
	}

	// a Monarch rule: [regex, action] or [regex, action, next state]
	static function rule(re:String, action:Dynamic, ?next:String):Array<Dynamic> {
		final r:Array<Dynamic> = [new RegExp(re), action];
		if (next != null) r.push(next);
		return r;
	}

	// Monarch tokenizer for Haxe
	static function defineHaxe() {
		final monaco:Dynamic = js.Lib.global.monaco;
		monaco.languages.register({id: "haxe", extensions: [".hx"]});
		monaco.languages.setLanguageConfiguration("haxe", {
			comments: {lineComment: "//", blockComment: ["/*", "*/"]},
			brackets: [["{", "}"], ["[", "]"], ["(", ")"]],
			autoClosingPairs: [{open: "{", close: "}"}, {open: "[", close: "]"}, {open: "(", close: ")"}, {open: '"', close: '"'}, {open: "'", close: "'"}],
		});
		monaco.languages.setMonarchTokensProvider("haxe", {
			keywords: [
				"abstract", "break", "case", "cast", "catch", "class", "continue", "default", "do", "dynamic", "else", "enum", "extends", "extern", "false", "final", "for",
				"function", "if", "implements", "import", "in", "inline", "interface", "macro", "new", "null", "operator", "overload", "override", "package", "private",
				"public", "return", "static", "switch", "this", "throw", "true", "try", "typedef", "untyped", "using", "var", "while", "from", "to", "is"
			],
			tokenizer: {
				root: ([
					rule("@:?[\\w.]+", "annotation"),
					rule("#(if|elseif|else|end|error)\\b.*$", "keyword.directive"),
					rule("[A-Z][\\w]*", "type.identifier"),
					rule("[a-z_$][\\w$]*", {cases: {"@keywords": "keyword", "@default": "identifier"}}),
					{include: "@whitespace"},
					rule("[{}()\\[\\]]", "@brackets"),
					rule("0x[0-9a-fA-F_]+", "number.hex"),
					rule("\\d[\\d_]*(\\.\\d+)?([eE][-+]?\\d+)?", "number"),
					rule("\"", "string", "@dstring"),
					rule("'", "string", "@sstring"),
					rule("~\\/(\\\\.|[^\\/\\\\])+\\/[gimsu]*", "regexp"),
					rule("[;,.]", "delimiter"),
					rule("[=><!~?:&|+\\-*\\/^%]+", "operator"),
				] : Array<Dynamic>),
				whitespace: [rule("[ \\t\\r\\n]+", ""), rule("\\/\\*", "comment", "@comment"), rule("\\/\\/.*$", "comment")],
				comment: [rule("[^\\/*]+", "comment"), rule("\\*\\/", "comment", "@pop"), rule("[\\/*]", "comment")],
				dstring: [rule("[^\\\\\"]+", "string"), rule("\\\\.", "string.escape"), rule("\"", "string", "@pop")],
				sstring: [
					rule("\\$\\{", "delimiter.bracket", "@interp"), rule("\\$\\w+", "variable"), rule("[^\\\\'$]+", "string"), rule("\\\\.", "string.escape"),
					rule("\\$", "string"), rule("'", "string", "@pop")
				],
				interp: ([rule("\\}", "delimiter.bracket", "@pop"), {include: "root"}] : Array<Dynamic>),
			},
		});
	}
}
