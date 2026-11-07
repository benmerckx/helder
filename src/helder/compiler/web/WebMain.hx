package helder.compiler.web;

import compiler.Args;
import compiler.io.CompilerIo;
import compiler.server.Server;
import compiler.server.ServerCache;
import haxe.io.Bytes;
import helder.compiler.service.Diagnostic;
import helder.compiler.service.LiteralEdit.Sources;

using StringTools;

// helder's compiler resident in a browser's worker (README.md): built as
// wasm32-wasi (build.mjs), its main installs helder's hooks (as
// helder.compiler.Compiler.run does), sets up a compilation server's
// context and hands the page its request function; then it returns, and
// the module and its heap stay alive between requests: Haxe's typed
// modules, hxmc's lowered bodies and objects, tsgo's session, the live
// literals' sources. A request is JSON (its UTF-8 bytes taken with
// WebHost.take), its answer JSON (WebHost.reply):
//
//   {kind: "compile", words, cwd}     a compilation server's request
//                                     (helder.compiler.service.Resident's):
//                                     {ok, printed, messages, diagnostics}
//   {kind: "entry", entry, target}    helder.cli.Entry's: {words, name, root, typescript}
//   {kind: "sources", dir}            the live literals' tables of the last
//                                     dev build read again (LiteralEdit.Sources)
//   {kind: "patches", file}           a save's live literals' patches:
//                                     {patches} or {why}
//   {kind: "took", list}              the patches the preview took
class WebMain {
	static var sctx:Null<compiler.server.ServerCompilationContext> = null;
	static var sources:Null<Sources> = null;
	static var std:Null<String> = null;

	static function main() {
		hxmc.Driver.resident = true;
		Compiler.install([]);
		std = Sys.getEnv("HXMC_STD");
		@:privateAccess haxe.Main.initHooks();
		sctx = Server.setupServerContext(false, true);
		WebHost.register(hxmc.unsafe.Callback.addr(request));
	}

	// the page's request, n bytes of UTF-8 JSON: answered through WebHost.reply (0), or 1 when it failed
	@:hxmc.callback static function request(n:Int):Int {
		var b = Bytes.alloc(n);
		hxmc.unsafe.Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			WebHost.take(p);
			hxmc.unsafe.BytesPtr.copyIn(b, 0, p, n);
		});
		var answer:Dynamic = try handle(haxe.Json.parse(b.toString())) catch (e:Dynamic) {error: Std.string(e)};
		Sys.stdout().flush();
		Sys.stderr().flush();
		reply(Bytes.ofString(haxe.Json.stringify(answer)));
		return answer.error == null ? 0 : 1;
	}

	@:hxmc.noGc static function reply(b:Bytes)
		WebHost.reply(hxmc.unsafe.BytesPtr.of(b, 0, b.length), b.length);

	static function handle(m:Dynamic):Dynamic {
		switch (m.kind : String) {
			case "compile":
				var words:Array<String> = m.words;
				return compile(["--cwd", m.cwd ?? "/"].concat(words).concat(std == null || words[0] == "--display" ? [] : ["-cp", std]));
			case "entry":
				if (m.cwd != null) Sys.setCwd(m.cwd);
				var e = helder.cli.Entry.resolve(m.entry, m.target ?? "web");
				return {words: e.args(), name: e.name, root: e.root, main: e.main, typescript: e.typescript};
			case "sources":
				if (sources == null || sources.dir != m.dir) sources = new Sources(m.dir);
				sources.update();
				return {};
			case "patches":
				if (sources == null) return {why: "live literals are off"};
				var why = null;
				var p = sources.patches(m.file, w -> why = w);
				return p == null ? {why: why ?? "removed"} : {patches: p};
			case "took":
				if (sources != null) sources.took(m.list);
				return {};
			case k:
				throw 'unknown request $k';
		}
	}

	// a request run as the compilation server runs one (Server's worker
	// loop), its answer read as Resident reads it: \x01 lines printed, \x02
	// failed, the rest messages
	static function compile(words:Array<String>):Dynamic {
		var out = new StringBuf();
		var conn:compiler.server.Server.ServerConnection = {
			read: () -> "",
			write: s -> out.add(s),
			close: () -> {},
			getStdin: () -> Server.makeClosedStdin()
		};
		var request:compiler.server.Server.Request = {args: Args.parseArgs(words), stdin: null, conn: conn};
		sctx.currentStdin = null;
		var io = requestIo(conn);
		@:privateAccess Server.runRequest(sctx, io, request);
		CompilerIo.close(io);
		ServerCache.cleanup(sctx);
		var ok = true, messages = [], printed = [];
		for (line in out.toString().split("\n")) {
			if (line.startsWith("\x01")) {
				var text = line.substr(1).split("\x01").join("\n");
				printed.push(text.endsWith("\n") ? text.substr(0, text.length - 1) : text);
			} else if (line.startsWith("\x02")) ok = false;
			else if (line != "") messages.push(line);
		}
		var text = messages.join("\n");
		return {ok: ok, printed: printed.join("\n"), messages: text, diagnostics: Diagnostics.parse(text)};
	}

	// Server.createRequestIo's channels without its reader threads (pipes
	// drained by a thread each; the worker has one): written through as
	// they are flushed
	static function requestIo(conn:compiler.server.Server.ServerConnection):compiler.io.CompilerIo.CompilerIoData {
		function writeOut(s:String) conn.write("\x01" + s.split("\n").join("\x01") + "\n");
		function writeErr(s:String) conn.write(s);
		var out = new Through(writeOut), err = new Through(writeErr);
		return {
			stdout: out,
			stderr: err,
			stdin: conn.getStdin(),
			getch: _ -> -1,
			writeOut: writeOut,
			writeErr: writeErr,
			writeResult: writeErr,
			signalError: () -> conn.write("\x02\n"),
			flush: () -> {
				out.flush();
				err.flush();
			},
			close: () -> {
				out.close();
				err.close();
			}
		};
	}
}

// an output kept until flushed, then handed on as text
private class Through extends haxe.io.Output {
	var buf = new haxe.io.BytesBuffer();
	final onText:String->Void;

	public function new(onText:String->Void)
		this.onText = onText;

	override function writeByte(c:Int)
		buf.addByte(c);

	override function writeBytes(b:Bytes, pos:Int, len:Int):Int {
		buf.addBytes(b, pos, len);
		return len;
	}

	override function flush() {
		if (buf.length == 0) return;
		var b = buf.getBytes();
		buf = new haxe.io.BytesBuffer();
		onText(b.toString());
	}

	override function close()
		flush();
}

// the worker's side (worker.mjs gives these imports)
@:hxmc.c @:hxmc.fast @:hxmc.lib("helder_compiler") extern class WebHost {
	// the request function (a @:hxmc.callback (n:Int):Int)
	static function register(f:hxmc.unsafe.Ptr):Void;
	// the request's bytes into p
	static function take(p:hxmc.unsafe.Ptr):Void;
	// the answer (UTF-8 JSON)
	static function reply(p:hxmc.unsafe.Ptr, n:Int):Void;
}
