import js.Syntax;
import js.lib.DataView;
import js.lib.Uint8Array;
import js.html.TextDecoder;
import js.html.TextEncoder;

// WASI preview 1 over a file system in memory: what the compiler
// (reactor.wasm: compiler/Reactor.hx) needs, in the page's worker
// (CompilerWorker) and in node (Check). One directory tree (MemFS)
// preopened as "/"; relative paths resolve against it (the compiler is
// given PWD=/work).
//
//   var fs = new MemFS();
//   fs.mount("/lib", Pack.unpack(bytes));
//   var w = new Wasi(["haxe"], env, fs);
//   var instance = new WebAssembly.Instance(module, {wasi_snapshot_preview1: w.imports, ...});
//   w.start(instance);                         // _start: the exit code
//
// onOpen(path, writing) is told of every file opened (the forge's sparks:
// sources read, objects written).

class Node {
	static var inodes = 1;

	public final ino:Int;
	public var mtime:Float;

	function new() {
		ino = inodes++;
		mtime = Date.now().getTime();
	}
}

class Dir extends Node {
	public final entries = new Map<String, Node>();
	// (the names in the order they were added: readdir's)
	public final order:Array<String> = [];

	public function new()
		super();

	public function get(name:String):Null<Node>
		return entries.get(name);

	public function set(name:String, n:Node) {
		if (!entries.exists(name)) order.push(name);
		entries.set(name, n);
	}

	public function remove(name:String) {
		if (entries.remove(name)) order.remove(name);
	}
}

class File extends Node {
	public var data:Uint8Array;
	public var size:Int;

	public function new(?data:Uint8Array) {
		super();
		this.data = data == null ? new Uint8Array(0) : data;
		size = this.data.length;
	}

	public function bytes():Uint8Array
		return data.subarray(0, size);

	public function reserve(n:Int) {
		if (n <= data.length) return;
		var d = new Uint8Array(Std.int(Math.max(n, Math.max(data.length * 2, 4096))));
		d.set(bytes());
		data = d;
	}

	public function touch()
		mtime = Date.now().getTime();
}

class MemFS {
	public final root = new Dir();

	public function new() {}

	// the parts of a path, "." dropped and ".." applied
	public static function split(path:String):Array<String> {
		var out = [];
		for (p in path.split("/")) {
			if (p == "" || p == ".") continue;
			if (p == "..") out.pop() else out.push(p);
		}
		return out;
	}

	public function lookup(path:String):Null<Node> {
		var n:Node = root;
		for (part in split(path)) {
			if (!(n is Dir)) return null;
			n = (cast n : Dir).get(part);
			if (n == null) return null;
		}
		return n;
	}

	public function mkdirs(path:String):Dir {
		var n = root;
		for (part in split(path)) {
			var c = n.get(part);
			if (c == null) n.set(part, c = new Dir());
			if (!(c is Dir)) throw '$path: not a directory';
			n = cast c;
		}
		return n;
	}

	public function write(path:String, data:Uint8Array) {
		var parts = split(path);
		var name = parts.pop();
		mkdirs(parts.join("/")).set(name, new File(data));
	}

	public function writeText(path:String, text:String)
		write(path, new TextEncoder().encode(text));

	public function read(path:String):Null<Uint8Array> {
		var n = lookup(path);
		return n is File ? (cast n : File).bytes() : null;
	}

	public function readText(path:String):Null<String> {
		var b = read(path);
		return b == null ? null : new TextDecoder().decode(b);
	}

	public function remove(path:String) {
		var parts = split(path);
		var name = parts.pop();
		var d = lookup(parts.join("/"));
		if (d is Dir) (cast d : Dir).remove(name);
	}

	public function mount(at:String, files:Array<Pack.Entry>)
		for (f in files) write(at + "/" + f.path, f.data);
}

// proc_exit, thrown through the module
class Exit {
	public final code:Int;

	public function new(code:Int)
		this.code = code;
}

private enum abstract Errno(Int) from Int to Int {
	var SUCCESS = 0;
	var BADF = 8;
	var EXIST = 20;
	var INVAL = 28;
	var ISDIR = 31;
	var NOENT = 44;
	var NOSYS = 52;
	var NOTDIR = 54;
	var NOTEMPTY = 55;
}

private typedef Fd = {node:Node, path:String, pos:Int, append:Bool};

class Wasi {
	public final imports:Dynamic;
	public var memory:js.lib.webassembly.Memory;
	public var onOpen:(path:String, writing:Bool) -> Void = (_, _) -> {};
	public var stdout:String->Void = _ -> {};
	public var stderr:String->Void = _ -> {};

	final fs:MemFS;
	final fds:Array<Null<Fd>>;
	final argv:Array<Uint8Array>;
	final envv:Array<Uint8Array>;
	final enc = new TextEncoder();
	final dec = new TextDecoder();
	final sinks:Array<{dec:TextDecoder, text:String}> = [null, {dec: new TextDecoder(), text: ""}, {dec: new TextDecoder(), text: ""}];

	public function new(args:Array<String>, env:Map<String, String>, fs:MemFS) {
		this.fs = fs;
		fds = [null, null, null, {node: fs.root, path: "/", pos: 0, append: false}];
		argv = [for (a in args) enc.encode(a + "\x00")];
		envv = [for (k => v in env) enc.encode('$k=$v\x00')];
		imports = {
			args_get: (ptrs:Int, buf:Int) -> strings(argv, ptrs, buf),
			args_sizes_get: (c:Int, s:Int) -> sizes(argv, c, s),
			environ_get: (ptrs:Int, buf:Int) -> strings(envv, ptrs, buf),
			environ_sizes_get: (c:Int, s:Int) -> sizes(envv, c, s),
			clock_time_get: clockTimeGet,
			clock_res_get: (_:Int, ptr:Int) -> {
				setU64(ptr, 1000);
				SUCCESS;
			},
			random_get: (p:Int, n:Int) -> {
				Syntax.code("crypto.getRandomValues({0})", u8().subarray(p, p + n));
				SUCCESS;
			},
			fd_close: (fd:Int) -> {
				if (fd <= 3 || fds[fd] == null) return BADF;
				fds[fd] = null;
				SUCCESS;
			},
			fd_fdstat_get: fdstatGet,
			fd_fdstat_set_flags: () -> SUCCESS,
			fd_filestat_get: (fd:Int, ptr:Int) -> {
				if (fd <= 2) return filestat(null, ptr);
				var f = fds[fd];
				f == null ? BADF : filestat(f.node, ptr);
			},
			fd_prestat_get: (fd:Int, ptr:Int) -> {
				if (fd != 3) return BADF;
				view().setUint8(ptr, 0);
				view().setUint32(ptr + 4, 1, true);
				SUCCESS;
			},
			fd_prestat_dir_name: (fd:Int, p:Int, n:Int) -> {
				if (fd != 3) return BADF;
				u8().set(enc.encode("/").subarray(0, n), p);
				SUCCESS;
			},
			fd_read: fdRead,
			fd_pread: () -> NOSYS,
			fd_pwrite: () -> NOSYS,
			fd_write: fdWrite,
			fd_seek: fdSeek,
			fd_tell: (fd:Int, ptr:Int) -> {
				var f = fds[fd];
				if (f == null) return BADF;
				setU64(ptr, f.pos);
				SUCCESS;
			},
			fd_sync: () -> SUCCESS,
			fd_datasync: () -> SUCCESS,
			fd_readdir: fdReaddir,
			path_open: pathOpen,
			path_filestat_get: (dirfd:Int, _:Int, p:Int, n:Int, ptr:Int) -> {
				var r = resolve(dirfd, p, n);
				if (r == null) return BADF;
				var node = r.name == null ? fs.root : r.parent?.get(r.name);
				node == null ? NOENT : filestat(node, ptr);
			},
			path_filestat_set_times: () -> SUCCESS,
			path_create_directory: (dirfd:Int, p:Int, n:Int) -> {
				var r = resolve(dirfd, p, n);
				if (r == null || r.parent == null) return NOENT;
				if (r.parent.get(r.name) != null) return EXIST;
				r.parent.set(r.name, new Dir());
				SUCCESS;
			},
			path_remove_directory: (dirfd:Int, p:Int, n:Int) -> {
				var r = resolve(dirfd, p, n);
				var node = r?.parent?.get(r.name);
				if (node == null) return NOENT;
				if (!(node is Dir)) return NOTDIR;
				if ((cast node : Dir).order.length > 0) return NOTEMPTY;
				r.parent.remove(r.name);
				SUCCESS;
			},
			path_unlink_file: (dirfd:Int, p:Int, n:Int) -> {
				var r = resolve(dirfd, p, n);
				var node = r?.parent?.get(r.name);
				if (node == null) return NOENT;
				if (node is Dir) return ISDIR;
				r.parent.remove(r.name);
				SUCCESS;
			},
			path_rename: (fd:Int, p:Int, n:Int, newFd:Int, np:Int, nn:Int) -> {
				var a = resolve(fd, p, n), b = resolve(newFd, np, nn);
				var node = a?.parent?.get(a.name);
				if (node == null || b == null || b.parent == null) return NOENT;
				a.parent.remove(a.name);
				b.parent.set(b.name, node);
				SUCCESS;
			},
			path_readlink: () -> INVAL,
			path_symlink: () -> NOSYS,
			path_link: () -> NOSYS,
			poll_oneoff: pollOneoff,
			proc_exit: (code:Int) -> throw new Exit(code),
			sched_yield: () -> SUCCESS,
		};
	}

	// runs _start (main); the exit code: 0 when main returns
	public function start(instance:js.lib.webassembly.Instance):Int {
		var exports:Dynamic = instance.exports;
		memory = exports.memory;
		try {
			exports._start();
			flush(1, true);
			flush(2, true);
			return 0;
		} catch (e:Exit) {
			flush(1, true);
			flush(2, true);
			return e.code;
		}
	}

	inline function view()
		return new DataView(memory.buffer);

	inline function u8()
		return new Uint8Array(memory.buffer);

	inline function str(p:Int, n:Int):String
		return dec.decode(u8().subarray(p, p + n));

	// (i64s: BigInt both ways)
	inline function setU64(ptr:Int, v:Float)
		Syntax.code("{0}.setBigUint64({1}, BigInt({2}), true)", view(), ptr, v);

	inline static function num(big:Dynamic):Float
		return Syntax.code("Number({0})", big);

	function flush(fd:Int, end = false) {
		var s = sinks[fd];
		var lines = s.text.split("\n");
		s.text = end ? "" : lines.pop();
		for (l in lines) if (l != "" || !end) (fd == 1 ? stdout : stderr)(l);
	}

	function strings(list:Array<Uint8Array>, ptrs:Int, buf:Int):Int {
		var v = view();
		for (s in list) {
			v.setUint32(ptrs, buf, true);
			ptrs += 4;
			u8().set(s, buf);
			buf += s.length;
		}
		return SUCCESS;
	}

	function sizes(list:Array<Uint8Array>, countPtr:Int, sizePtr:Int):Int {
		var n = 0;
		for (s in list) n += s.length;
		view().setUint32(countPtr, list.length, true);
		view().setUint32(sizePtr, n, true);
		return SUCCESS;
	}

	function clockTimeGet(id:Int, _:Dynamic, ptr:Int):Int {
		var ns = id == 0 ? Date.now().getTime() * 1e6 : Math.round(js.Lib.global.performance.now() * 1e6);
		setU64(ptr, ns);
		return SUCCESS;
	}

	// a path given relative to a directory fd: its parent, its name, the whole path
	function resolve(dirfd:Int, p:Int, n:Int):Null<{parent:Null<Dir>, name:Null<String>, full:String}> {
		var d = fds[dirfd];
		if (d == null || !(d.node is Dir)) return null;
		var rel = str(p, n);
		var parts = MemFS.split(StringTools.startsWith(rel, "/") ? rel : d.path + "/" + rel);
		var name = parts.pop();
		var parent = fs.lookup(parts.join("/"));
		if (name != null) parts.push(name);
		return {parent: parent is Dir ? cast parent : null, name: name, full: "/" + parts.join("/")};
	}

	function filestat(node:Null<Node>, ptr:Int):Int {
		var v = view();
		setU64(ptr, 0);
		setU64(ptr + 8, node == null ? 0 : node.ino);
		v.setUint8(ptr + 16, node is Dir ? 3 : node != null ? 4 : 2);
		setU64(ptr + 24, 1);
		setU64(ptr + 32, node is File ? (cast node : File).size : 0);
		var t = node == null ? 0 : node.mtime * 1e6;
		setU64(ptr + 40, t);
		setU64(ptr + 48, t);
		setU64(ptr + 56, t);
		return SUCCESS;
	}

	function fdstatGet(fd:Int, ptr:Int):Int {
		var f = fds[fd];
		if (fd > 2 && f == null) return BADF;
		var v = view();
		v.setUint8(ptr, fd <= 2 ? 2 : f.node is Dir ? 3 : 4);
		v.setUint16(ptr + 2, f != null && f.append ? 1 : 0, true);
		setU64(ptr + 8, 0xffffffff);
		setU64(ptr + 16, 0xffffffff);
		return SUCCESS;
	}

	function fdRead(fd:Int, iovs:Int, n:Int, nread:Int):Int {
		var v = view();
		if (fd == 0) {
			v.setUint32(nread, 0, true);
			return SUCCESS;
		}
		var f = fds[fd];
		if (f == null) return BADF;
		if (!(f.node is File)) return ISDIR;
		var m = u8(), data = (cast f.node : File).bytes(), total = 0;
		for (i in 0...n) {
			var p = v.getUint32(iovs + i * 8, true), len = v.getUint32(iovs + i * 8 + 4, true);
			var chunk = data.subarray(f.pos, f.pos + len);
			m.set(chunk, p);
			f.pos += chunk.length;
			total += chunk.length;
			if (chunk.length < len) break;
		}
		v.setUint32(nread, total, true);
		return SUCCESS;
	}

	function fdWrite(fd:Int, iovs:Int, n:Int, nwritten:Int):Int {
		var v = view(), m = u8(), total = 0;
		var f = fds[fd];
		if (fd > 2 && (f == null || !(f.node is File))) return BADF;
		for (i in 0...n) {
			var p = v.getUint32(iovs + i * 8, true), len = v.getUint32(iovs + i * 8 + 4, true);
			var chunk = m.subarray(p, p + len);
			if (fd == 1 || fd == 2) {
				var s = sinks[fd];
				s.text += s.dec.decode(chunk, {stream: true});
				flush(fd);
			} else {
				var file:File = cast f.node;
				if (f.append) f.pos = file.size;
				file.reserve(f.pos + len);
				file.data.set(chunk, f.pos);
				f.pos += len;
				if (f.pos > file.size) file.size = f.pos;
				file.touch();
			}
			total += len;
		}
		v.setUint32(nwritten, total, true);
		return SUCCESS;
	}

	function fdSeek(fd:Int, offset:Dynamic, whence:Int, ptr:Int):Int {
		var f = fds[fd];
		if (f == null || !(f.node is File)) return BADF;
		var base = whence == 0 ? 0 : whence == 1 ? f.pos : (cast f.node : File).size;
		var pos = Std.int(base + num(offset));
		if (pos < 0) return INVAL;
		f.pos = pos;
		setU64(ptr, pos);
		return SUCCESS;
	}

	function fdReaddir(fd:Int, buf:Int, len:Int, cookie:Dynamic, used:Int):Int {
		var f = fds[fd];
		if (f == null || !(f.node is Dir)) return NOTDIR;
		var dir:Dir = cast f.node;
		var m = u8(), at = buf, end = buf + len;
		var i = Std.int(num(cookie));
		while (i < dir.order.length && at < end) {
			var name = enc.encode(dir.order[i]);
			var node = dir.get(dir.order[i]);
			var entry = new Uint8Array(24 + name.length);
			var ev = new DataView(entry.buffer);
			Syntax.code("{0}.setBigUint64(0, BigInt({1}), true)", ev, i + 1);
			Syntax.code("{0}.setBigUint64(8, BigInt({1}), true)", ev, node.ino);
			ev.setUint32(16, name.length, true);
			ev.setUint8(20, node is Dir ? 3 : 4);
			entry.set(name, 24);
			// (the last one cut at the end of the buffer: the caller reads again from its cookie)
			var k = Std.int(Math.min(entry.length, end - at));
			m.set(entry.subarray(0, k), at);
			at += k;
			i++;
		}
		view().setUint32(used, at - buf, true);
		return SUCCESS;
	}

	function pathOpen(dirfd:Int, _:Int, p:Int, n:Int, oflags:Int, _:Dynamic, _:Dynamic, fdflags:Int, fdPtr:Int):Int {
		var r = resolve(dirfd, p, n);
		if (r == null) return BADF;
		if (r.parent == null && r.name != null) return NOENT;
		var node = r.name == null ? fs.root : r.parent.get(r.name);
		if (node != null && oflags & 4 != 0 && oflags & 1 != 0) return EXIST;
		if (node == null) {
			if (oflags & 1 == 0) return NOENT;
			r.parent.set(r.name, node = new File());
		}
		if (oflags & 2 != 0 && !(node is Dir)) return NOTDIR;
		if (oflags & 8 != 0 && node is File) (cast node : File).size = 0;
		var fd = 4;
		while (fds[fd] != null) fd++;
		fds[fd] = {node: node, path: r.full, pos: 0, append: fdflags & 1 != 0};
		if (node is File) onOpen(r.full, oflags & 1 != 0);
		view().setUint32(fdPtr, fd, true);
		return SUCCESS;
	}

	// (clock subscriptions fire at once: nothing here waits)
	function pollOneoff(inp:Int, out:Int, nsubs:Int, nevents:Int):Int {
		var v = view();
		for (i in 0...nsubs) {
			var s = inp + i * 48, e = out + i * 32;
			Syntax.code("{0}.setBigUint64({1}, {0}.getBigUint64({2}, true), true)", v, e, s);
			v.setUint16(e + 8, 0, true);
			v.setUint8(e + 10, v.getUint8(s + 8));
		}
		v.setUint32(nevents, nsubs, true);
		return SUCCESS;
	}
}
