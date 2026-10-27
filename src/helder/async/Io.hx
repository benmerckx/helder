package helder.async;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.coro.IContinuation;
import sys.net.Socket as NetSocket;

// The loop's I/O, completion-based (as io_uring and IOCP are): an
// operation is submitted (accept, connect, read into a buffer, write, a
// process's exit), and comes back completed (its result in it, or its
// error) through its continuation, on the loop. The operation owns its
// buffer until then. `poll` waits at most `seconds` (-1: until one
// completes) and delivers what completed; timeouts are the loop's timers,
// whose next one bounds the wait. One backend for now, select(2)
// (SelectIo), which emulates completions: it waits for readiness, then
// makes the call. io_uring (Linux, select where it is disabled), kqueue
// (macOS) and IOCP (Windows) are other implementations of this interface.
interface Backend {
	function submit(op:Op):Void;
	// the operation dropped (its continuation not resumed)
	function cancel(op:Op):Void;
	function pending():Int;
	function poll(seconds:Float):Void;
}

enum abstract OpKind(Int) {
	var Accept;
	var Connect;
	var Read;
	var Write;
	var Exit;
}

// what an operation is done on: a socket, or a pipe (natively on POSIX its
// descriptor, polled like a socket; elsewhere, and on Eval, a stream read
// and written by threads)
class Handle {
	public final socket:Null<NetSocket>;
	public final fd:Int;
	public final input:Null<haxe.io.Input>;
	public final output:Null<haxe.io.Output>;
	public var closed = false;
	// (threaded: the chunks read so far, null at the end; the thread started)
	var chunks:Null<Array<Null<Bytes>>>;
	var error:Null<Exception>;

	public function new(socket:Null<NetSocket>, fd = -1, ?input:haxe.io.Input, ?output:haxe.io.Output) {
		this.socket = socket;
		this.fd = fd;
		this.input = input;
		this.output = output;
	}

	// a pipe's descriptor (POSIX, natively): a socket's shell for select
	public static function ofFd(fd:Int):Handle {
		#if eval
		throw "helder.async: descriptors are native";
		#else
		var s:NetSocket = Type.createEmptyInstance(NetSocket);
		@:privateAccess s.fd = fd;
		return new Handle(s, fd);
		#end
	}
}

// an operation: its arguments, then its result
class Op {
	public final kind:OpKind;
	public final handle:Null<Handle>;
	// Read, Write: the buffer (owned by the operation until it completes)
	public final buf:Null<Bytes>;
	public final pos:Int;
	public final len:Int;
	// Connect: where; Exit: the process (pid, or the threaded process)
	public final host:String;
	public final port:Int;
	public final process:Null<Dynamic>;
	// the result: bytes read (0 at the end) or written, an exit code; an
	// accepted socket; or the error
	public var result = 0;
	public var socket:Null<NetSocket>;
	public var error:Null<Exception>;
	public var cont:Null<IContinuation<Op>>;

	public function new(kind, handle, ?buf, pos = 0, len = 0, host = "", port = 0, ?process) {
		this.kind = kind;
		this.handle = handle;
		this.buf = buf;
		this.pos = pos;
		this.len = len;
		this.host = host;
		this.port = port;
		this.process = process;
	}

	// submitted to the loop's backend; done: this op, or its error thrown
	@:coroutine public function run():Op {
		var op = this;
		var io = Async.loopOf(Async.context()).io;
		Async.suspendCancellable(cont -> {
			op.cont = cont;
			io.submit(op);
			return _ -> io.cancel(op);
		});
		if (error != null) throw error;
		return this;
	}
}

class Backends {
	public static function create(loop:Loop):Backend
		return #if (hxmc.target == "wasm32-wasi") new NoIo() #else new SelectIo(loop) #end;
}

// select(2) (sys.net.Socket.select: hxmc's, Eval's) and threads for what it
// cannot wait on: pipes on Windows and Eval, a process's exit there (natively
// on POSIX a waitpid at each poll, the wait at most 10 ms meanwhile).
// FD_SETSIZE: 1024 descriptors. A connect or write waits for the socket's
// errors too (Windows reports a failed connect there).
class SelectIo implements Backend {
	final loop:Loop;
	final ops:Array<Op> = [];
	var exits = 0;

	public function new(loop) {
		this.loop = loop;
	}

	public function pending():Int
		return ops.length;

	public function cancel(op:Op) {
		if (ops.remove(op) && op.kind == Exit) exits--;
		op.cont = null;
	}

	public function submit(op:Op) {
		var h = op.handle;
		if (op.kind == Connect) {
			// (non-blocking: in progress, done once writable; Eval: done now)
			h.socket.setBlocking(false);
			try h.socket.connect(new sys.net.Host(op.host), op.port) catch (e:Dynamic) {
				var s = Std.string(e);
				if (s.indexOf("progress") < 0 && s.indexOf("Blocked") < 0 && s.indexOf("would block") < 0) return complete(op, new Exception('connect to ${op.host}:${op.port}: $s'));
			}
		}
		if (op.kind == Exit) exits++;
		if (h != null && h.socket == null && op.kind == Read) start(h);
		ops.push(op);
		if (op.kind == Exit ? !(op.process is Int) : h.socket == null) threaded(op);
	}

	public function poll(seconds:Float) {
		if (exits > 0 || loop.held > 0) seconds = seconds < 0 || seconds > 0.01 ? 0.01 : seconds;
		var r = [], w = [];
		for (op in ops)
			if (op.handle != null && op.handle.socket != null) (op.kind == Connect || op.kind == Write ? w : r).push(op.handle.socket);
		if (r.length + w.length == 0) {
			if (seconds > 0) Sys.sleep(seconds);
		} else {
			var s = try NetSocket.select(r, w, w, seconds < 0 ? null : seconds) catch (e:Dynamic) null;
			for (op in ops.copy()) {
				var sock = op.handle?.socket;
				if (sock == null) continue;
				var ready = if (s == null) bad(op) else if (op.kind == Connect || op.kind == Write) s.write.contains(sock) || s.others.contains(sock) else s.read.contains(sock);
				if (ready) attempt(op);
			}
		}
		if (exits > 0) for (op in ops.copy())
			if (op.kind == Exit && op.process is Int) {
				var c = Process.exited(op.process);
				if (c >= 0) {
					op.result = c;
					done(op);
				}
			}
	}

	// readiness: the call, unless it would block after all
	function attempt(op:Op) {
		var s = op.handle.socket;
		try {
			switch op.kind {
				case Accept:
					op.socket = s.accept();
				case Connect:
					try s.peer() catch (e:Dynamic) throw new Exception('connect to ${op.host}:${op.port}: refused');
				case Read if (op.handle.fd >= 0):
					#if !eval
					var n = hxmc.NativeSys.fileRead(op.handle.fd, op.buf, op.pos, op.len);
					if (n < 0) return;
					op.result = n;
					#end
				case Read:
					op.result = try s.input.readBytes(op.buf, op.pos, op.len) catch (e:haxe.io.Eof) 0;
				case Write if (op.handle.fd >= 0):
					#if !eval
					var n = hxmc.NativeSys.fileWrite(op.handle.fd, op.buf, op.pos, op.len);
					if (n < 0) return;
					op.result = n;
					#end
				case Write:
					op.result = s.output.writeBytes(op.buf, op.pos, op.len);
				case Exit:
			}
		} catch (e:haxe.io.Error) {
			if (e == Blocked) return;
			op.error = new Exception(Std.string(e));
		} catch (e:Exception) {
			op.error = e;
		} catch (e:Dynamic) {
			op.error = new Exception(Std.string(e));
		}
		done(op);
	}

	// (select failed: a socket closed meanwhile, found alone)
	function bad(op:Op):Bool
		return try {
			var w = op.kind == Connect || op.kind == Write;
			NetSocket.select(w ? [] : [op.handle.socket], w ? [op.handle.socket] : [], [], 0);
			false;
		} catch (e:Dynamic) {
			op.error = new Exception("closed");
			done(op);
			false;
		}

	function done(op:Op) {
		if (ops.remove(op) && op.kind == Exit) exits--;
		complete(op, op.error);
	}

	function complete(op:Op, e:Null<Exception>) {
		op.error = e;
		var c = op.cont;
		op.cont = null;
		if (c != null) Async.resumeLater(c, op, null);
	}

	// ---- threads: a reader per input, from its first read on; a write
	// written at once; an exit waited for by a thread of its own

	function start(h:Handle) {
		@:privateAccess if (h.chunks != null) return;
		@:privateAccess h.chunks = [];
		#if target.threaded
		var loop = loop;
		loop.hold();
		sys.thread.Thread.create(() -> {
			var b = Bytes.alloc(16384);
			while (true) {
				var n = try h.input.readBytes(b, 0, b.length) catch (e:Dynamic) 0;
				var chunk = n > 0 ? b.sub(0, n) : null;
				loop.post(() -> {
					@:privateAccess h.chunks.push(chunk);
					if (chunk == null) loop.release();
					feed(h);
				});
				if (n == 0) break;
			}
		});
		#else
		@:privateAccess h.error = new Exception("helder.async: no threads here");
		#end
	}

	function threaded(op:Op) {
		switch op.kind {
			case Read:
				feed(op.handle);
			case Write:
				try {
					op.handle.output.writeBytes(op.buf, op.pos, op.len);
					op.result = op.len;
				} catch (e:Dynamic) op.error = new Exception(Std.string(e));
				done(op);
			case Exit if (!(op.process is Int)):
				#if target.threaded
				var loop = loop, p:sys.io.Process = op.process;
				loop.hold();
				sys.thread.Thread.create(() -> {
					var c = p.exitCode();
					loop.post(() -> {
						loop.release();
						op.result = c;
						done(op);
					});
				});
				#end
			case _:
		}
	}

	// the reads waiting on a threaded input, from its chunks
	function feed(h:Handle) {
		@:privateAccess var chunks = h.chunks;
		for (op in ops.copy()) {
			if (op.handle != h || op.kind != Read || chunks.length == 0) continue;
			var c = chunks[0];
			if (c == null) op.result = 0 else {
				var n = c.length < op.len ? c.length : op.len;
				op.buf.blit(op.pos, c, 0, n);
				op.result = n;
				if (n == c.length) chunks.shift() else chunks[0] = c.sub(n, c.length - n);
			}
			done(op);
		}
	}
}

class NoIo implements Backend {
	public function new() {}

	public function submit(op:Op)
		throw new Exception("helder.async: no sockets or processes here");

	public function cancel(op:Op) {}

	public function pending():Int
		return 0;

	public function poll(seconds:Float) {}
}
