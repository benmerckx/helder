import compiler.Args;
import compiler.Helper;
import compiler.io.CompilerIo.CompilerIoData;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import compiler.server.Server;
import compiler.server.ServerCache;
import compiler.server.ServerCompilationContext;
import hxmc.unsafe.Callback;
import hxmc.web.WasmBridge;

// The landing page's compiler: hxmc's `haxe` (hxmc.HaxeMain, @hxmc/wasm) as
// a compilation server that stays in its worker. main sets the compiler up
// as `haxe --wait` would and returns; the page then calls request (a
// @:hxmc.callback, named to it through hxmc_web's define as Exports does)
// with each build's arguments, an hxml string, and gets the server's
// answer: the output as the server's clients get it (stdout lines marked
// \x01, \x02 before the errors of a failed build). Typed modules, lowered
// bodies and compiled objects stay in memory between requests, as with
// `hxmc dev`, so a build after an edit types only what changed, and a
// display request (--display, JSON-RPC: completion, hover, signature help)
// reuses the last build's modules.
//
// Built by the repository's tool from hxmc's sources (landing/build/Build.hx, make landing):
//   -cp haxe/src -cp hxmc/src -cp packages/web/src -cp landing/compiler -main Reactor
class Reactor {
	static var sctx:ServerCompilationContext;
	// (the request's --no-output: a type check, nothing generated)
	static var noOutput = false;

	static function main() {
		// what hxmc.HaxeMain.run installs, the module cache aside (the server keeps modules in memory)
		hxmc.Defines.install();
		hxmc.ir.CInterop.install();
		hxmc.TargetFlags.install();
		hxmc.Driver.resident = true;
		compiler.Compiler.generateHook = function(com) {
			if (noOutput) return;
			switch com.platform {
				case CustomTarget("hxmc"):
				case _: return;
			}
			try {
				if (!core.Define.rawDefined(com.defines, "hxmc.target")) core.Define.rawDefineValue(com.defines, "hxmc.target", "wasm32-wasi");
				@:privateAccess hxmc.Main.generate(com, com.file);
			} catch (e:Dynamic) {
				com.error("hxmc: " + Std.string(e), core.Globals.nullPos);
			}
		}
		haxe.Main.initHooks();
		sctx = @:privateAccess Server.setupServerContext(false, true);
		WasmBridge.start();
		WasmBridge.define("request", Callback.addr(Reactor.request));
	}

	// a request's IO as Server.createRequestIo makes it, without its pipes'
	// threads (none in wasm32-wasi): the program's output (trace, --interp)
	// written to the connection at once, as the server's clients get it
	static function io(conn:ServerConnection):CompilerIoData {
		function writeOut(s:String) conn.write("\x01" + s.split("\n").join("\x01") + "\n");
		var stdout = new LineOutput(writeOut), stderr = new LineOutput(conn.write), stdin = Server.makeClosedStdin();
		return {
			stdout: stdout,
			stderr: stderr,
			stdin: stdin,
			getch: (_) -> -1,
			writeOut: writeOut,
			writeErr: conn.write,
			writeResult: conn.write,
			signalError: () -> conn.write("\x02\n"),
			flush: () -> {
				stdout.flush();
				stderr.flush();
			},
			close: () -> {
				stdout.flush();
				stderr.flush();
			},
		};
	}

	// one request: the n bytes at p, an hxml string; the server's answer (WasmBridge.stringOut)
	@:hxmc.callback static function request(p:Int, n:Int):Int {
		var hxml = WasmBridge.bytesIn(p, n).toString();
		var out = new StringBuf();
		var conn:ServerConnection = {
			read: () -> "",
			write: (s:String) -> out.add(s),
			close: () -> {},
			getStdin: Server.makeClosedStdin,
		};
		var args = Helper.parseHxmlData(hxml);
		noOutput = args.contains("--no-output");
		var request:Request = {args: Args.parseArgs(args), stdin: null, conn: conn};
		@:privateAccess Server.runRequest(sctx, io(conn), request);
		sctx.currentStdin = null;
		ServerCache.cleanup(sctx);
		return WasmBridge.stringOut(out.toString());
	}
}

// an Output buffered until flushed, then given to write as a string
class LineOutput extends haxe.io.Output {
	final send:String->Void;
	var buffer = new BytesBuffer();

	public function new(send:String->Void)
		this.send = send;

	override public function writeByte(c:Int)
		buffer.addByte(c);

	override public function writeBytes(b:Bytes, pos:Int, len:Int):Int {
		buffer.addBytes(b, pos, len);
		return len;
	}

	override public function flush() {
		if (buffer.length == 0) return;
		var s = buffer.getBytes().toString();
		buffer = new BytesBuffer();
		send(s);
	}
}
