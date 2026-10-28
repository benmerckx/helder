package helder.typescript.check;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.typescript.check.Syntax;

// A tsgo API server (`tsc --api`), driven synchronously over its stdio pipes.
// Each message is a msgpack array [type, method, payload]; requests carry
// JSON, and source files come back in tsgo's binary AST encoding.
class Tsgo {
	static inline var REQUEST = 1;
	static inline var RESPONSE = 4;
	static inline var ERROR = 5;
	static inline var CALL = 6;
	static inline var CALL_ERROR = 3;
	var process:sys.io.Process;
	var input:haxe.io.Output;
	var output:haxe.io.Input;
	public function new(executable:String, cwd:String) {
		process = new sys.io.Process(executable, ["--api", "--cwd", cwd, "--useCaseSensitiveFileNames=" + (Sys.systemName() != "Windows" && Sys.systemName() != "Mac")]);
		input = process.stdin;
		output = process.stdout;
	}

	// The typescript package (7.1 or later) installed for a file, from its
	// directory up, then from the working directory up (HELDER_TYPESCRIPT
	// names another), and its platform package's tsgo.
	public static function find(from:String):{typescript:String, exe:String} {
		var configured = Sys.getEnv("HELDER_TYPESCRIPT");
		var dir = configured != null && configured != "" ? configured : null;
		if (dir == null) for (start in [from, Sys.getCwd()]) {
			var d = sys.FileSystem.fullPath(start);
			while (dir == null && d != null && d != "") {
				if (sys.FileSystem.exists(d + "/node_modules/typescript/dist/api/node/protocol.js")) dir = d + "/node_modules/typescript";
				var up = haxe.io.Path.directory(d);
				if (up == d || up == "") break;
				d = up;
			}
		}
		if (dir == null) throw "TSHX003: typescript is not installed (npm install -D typescript@^7.1)";
		dir = sys.FileSystem.fullPath(dir);
		var platform = switch (Sys.systemName()) {
			case "Windows": "win32";
			case "Mac": "darwin";
			case _: "linux";
		};
		var exe = Sys.systemName() == "Windows" ? "tsc.exe" : "tsc";
		for (base in [dir + "/node_modules/@typescript", haxe.io.Path.directory(dir) + "/@typescript"]) for (arch in ["x64", "arm64"]) {
			var path = base + "/typescript-" + platform + "-" + arch + "/lib/" + exe;
			if (sys.FileSystem.exists(path)) return {typescript: dir, exe: path};
		}
		throw "TSHX003: " + dir + " has no tsgo for this platform (@typescript/typescript-" + platform + "-*)";
	}

	public function call(method:String, params:Dynamic):Dynamic {
		var result = request(method, haxe.Json.stringify(params));
		return result.length == 0 ? null : haxe.Json.parse(result.toString());
	}

	public function request(method:String, payload:String):Bytes {
		var name = Bytes.ofString(method), body = Bytes.ofString(payload);
		var b = new BytesBuffer();
		b.addByte(0x93);
		b.addByte(REQUEST);
		bin(b, name);
		bin(b, body);
		input.write(b.getBytes());
		input.flush();
		while (true) {
			if (output.readByte() != 0x93) throw "TSHX003: malformed tsgo message";
			var type = output.readByte();
			if (type == 0xcc) type = output.readByte();
			var from = readBin().toString(), data = readBin();
			switch (type) {
				case RESPONSE: return data;
				case ERROR: throw "TSHX003: tsgo " + method + ": " + data.toString();
				case CALL:
					var b = new BytesBuffer();
					b.addByte(0x93);
					b.addByte(CALL_ERROR);
					bin(b, Bytes.ofString(from));
					bin(b, Bytes.ofString("no callbacks"));
					input.write(b.getBytes());
					input.flush();
				case _: throw "TSHX003: unexpected tsgo message " + type;
			}
		}
	}

	static function bin(b:BytesBuffer, data:Bytes) {
		var n = data.length;
		if (n < 256) {
			b.addByte(0xc4);
			b.addByte(n);
		}
		else if (n < 65536) {
			b.addByte(0xc5);
			b.addByte(n >> 8);
			b.addByte(n & 0xff);
		}
		else {
			b.addByte(0xc6);
			b.addByte(n >>> 24);
			b.addByte((n >> 16) & 0xff);
			b.addByte((n >> 8) & 0xff);
			b.addByte(n & 0xff);
		}
		b.add(data);
	}

	function readBin():Bytes {
		var n = switch (output.readByte()) {
			case 0xc4: output.readByte();
			case 0xc5:
				var h = output.readByte();
				(h << 8) | output.readByte();
			case 0xc6:
				var a = output.readByte(), b = output.readByte(), c = output.readByte();
				(a << 24) | (b << 16) | (c << 8) | output.readByte();
			case m: throw "TSHX003: malformed tsgo payload " + m;
		};
		return n == 0 ? Bytes.alloc(0) : output.read(n);
	}

	public function close() {
		try {
			input.close();
			process.kill();
			process.close();
		} catch (_:Dynamic) {}
	}
}
