package helder.async;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.coro.IContinuation;
import sys.net.Socket as NetSocket;
#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
import hxmc.NativeSys;
import hxmc.net.Poll;

using hxmc.net.SocketTools;
#end

// The loop's I/O, completion-based (as io_uring and IOCP are): an
// operation is submitted (accept, connect, read into a buffer, write, a
// process's exit), and comes back completed (its result in it, or its
// error) through its continuation, on the loop. The operation owns its
// buffer until then. `poll` waits at most `seconds` (-1: until one
// completes) and delivers what completed; timeouts are the loop's timers,
// whose next one bounds the wait. Natively the backend is poll(2)
// (PollIo: hxmc.net.Poll), on Eval select(2) (SelectIo); both emulate
// completions: they wait for readiness, then make the call. io_uring
// (Linux, poll where it is disabled), kqueue (macOS) and IOCP (Windows) are
// other implementations of this interface.
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

// what an operation is done on: a socket, or a pipe (natively its
// descriptor: on POSIX polled like a socket, on Windows read and written by
// threads; on Eval a stream, read and written by threads)
class Handle {
	public static final WINDOWS = #if (target.name == "hxmc" && hxmc.target != "wasm32-wasi") hxmc.unsafe.Mem.os() == 2 #else Sys.systemName() == "Windows" #end;

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

	// waited on by the backend (else read and written by threads)
	public inline function polled():Bool
		return socket != null || (fd >= 0 && !WINDOWS);
}

// an operation: its arguments, then its result
class Op {
	public final kind:OpKind;
	public final handle:Null<Handle>;
	// Read, Write: the buffer (owned by the operation until it completes)
	public final buf:Null<Bytes>;
	public final pos:Int;
	public final len:Int;
	// Connect: where; Exit: the process
	public final host:String;
	public final port:Int;
	public final process:Null<Process>;
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
		return #if (hxmc.target == "wasm32-wasi") new NoIo() #elseif (target.name == "hxmc") new PollIo(loop) #else new SelectIo(loop) #end;
}

// What the readiness backends share: the operations waiting, their
// completion, and threads for what cannot be waited on (pipes on Windows and
// Eval, a process's exit there: a reader per input from its first read on, a
// write written at once, an exit waited for by a thread of its own). A
// process's exit with no descriptor to wait on (macOS) is asked for at each
// poll, the wait at most 10 ms meanwhile.
class ReadyIo implements Backend {
	final loop:Loop;
	final ops:Array<Op> = [];
	// (the exits asked for at each poll)
	var asked = 0;

	public function new(loop) {
		this.loop = loop;
	}

	public function pending():Int
		return ops.length;

	public function cancel(op:Op) {
		if (ops.remove(op) && asks(op)) asked--;
		op.cont = null;
	}

	public function submit(op:Op) {
		if (op.kind == Connect && !connect(op)) return;
		var h = op.handle;
		if (op.kind == Read && !h.polled()) start(h);
		ops.push(op);
		if (op.kind == Exit) {
			if (asks(op)) asked++ else if (!exitPolled(op.process)) waitExit(op);
		} else if (!h.polled()) threaded(op);
	}

	public function poll(seconds:Float) {}

	// (a connect started: false when it failed at once, completed)
	function connect(op:Op):Bool
		return true;

	// (a process's exit: on a descriptor the backend waits on)
	function exitPolled(p:Process):Bool
		return false;

	// (a process's exit: asked for at each poll, natively without a descriptor
	// for it, but on Windows)
	function asks(op:Op):Bool
		return op.kind == Exit && op.process.proc == null && !exitPolled(op.process) && !Handle.WINDOWS;

	// the exits asked for (waitpid without blocking)
	function ask() {
		var i = ops.length;
		while (i-- > 0) {
			var op = ops[i];
			if (asks(op)) {
				var c = op.process.poll();
				if (c >= 0) exited(op.process, c);
			}
		}
	}

	// a process exited: every wait for it done
	function exited(p:Process, code:Int) {
		p.reaped(code);
		var i = ops.length;
		while (i-- > 0) {
			var op = ops[i];
			if (op.kind == Exit && op.process == p) {
				op.result = code;
				done(op);
			}
		}
	}

	function done(op:Op) {
		if (ops.remove(op) && asks(op)) asked--;
		complete(op, op.error);
	}

	function complete(op:Op, e:Null<Exception>) {
		op.error = e;
		var c = op.cont;
		op.cont = null;
		if (c != null) Async.resumeLater(c, op, null);
	}

	// ---- threads

	function start(h:Handle) {
		@:privateAccess if (h.chunks != null) return;
		@:privateAccess h.chunks = [];
		#if target.threaded
		var loop = loop;
		loop.hold();
		sys.thread.Thread.create(() -> {
			var b = Bytes.alloc(16384);
			while (true) {
				var n = try read(h, b) catch (e:Dynamic) 0;
				var chunk = n > 0 ? b.sub(0, n) : null;
				loop.post(() -> {
					@:privateAccess h.chunks.push(chunk);
					if (chunk == null) loop.release();
					feed(h);
				});
				if (n <= 0) break;
			}
		});
		#else
		@:privateAccess h.error = new Exception("helder.async: no threads here");
		#end
	}

	// (a blocking read, on a reader's thread: 0 at the end)
	static function read(h:Handle, b:Bytes):Int {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (h.fd >= 0) return NativeSys.fileRead(h.fd, b, 0, b.length);
		#end
		return h.input.readBytes(b, 0, b.length);
	}

	function threaded(op:Op) {
		switch op.kind {
			case Read:
				feed(op.handle);
			case Write:
				try {
					var h = op.handle;
					#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
					if (h.fd >= 0) {
						var at = op.pos, end = op.pos + op.len;
						while (at < end) {
							var n = NativeSys.fileWrite(h.fd, op.buf, at, end - at);
							if (n < 0) throw "write failed";
							at += n;
						}
					} else
					#end
					h.output.writeBytes(op.buf, op.pos, op.len);
					op.result = op.len;
				} catch (e:Dynamic) op.error = new Exception(Std.string(e));
				done(op);
			case _:
		}
	}

	// an exit waited for by a thread (Windows natively; Eval)
	function waitExit(op:Op) {
		#if target.threaded
		var loop = loop, p = op.process;
		if (p.waited) return;
		p.waited = true;
		loop.hold();
		sys.thread.Thread.create(() -> {
			var c = if (p.proc != null) p.proc.exitCode() else {
				#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
				NativeSys.processWait(p.pid, true);
				#else
				-1;
				#end
			}
			loop.post(() -> {
				loop.release();
				exited(p, c);
			});
		});
		#end
	}

	// the reads waiting on a threaded input, from its chunks
	function feed(h:Handle) {
		@:privateAccess var chunks = h.chunks;
		var i = 0;
		while (i < ops.length) {
			var op = ops[i++];
			if (op.handle != h || op.kind != Read || chunks.length == 0) continue;
			var c = chunks[0];
			if (c == null) op.result = 0 else {
				var n = c.length < op.len ? c.length : op.len;
				op.buf.blit(op.pos, c, 0, n);
				op.result = n;
				if (n == c.length) chunks.shift() else chunks[0] = c.sub(n, c.length - n);
			}
			done(op);
			i--;
		}
	}
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// poll(2) (hxmc.net.Poll.wait: no allocation, any descriptor): sockets,
// pipes' descriptors and Linux's pidfds; on Windows (WSAPoll: sockets only)
// pipes and exits on threads (ReadyIo). A connect waits for writability,
// then reads its outcome (SocketTools.connectError).
class PollIo extends ReadyIo {
	// (the descriptors of the last wait, reused: their events, the ready ones, their operations)
	final fds:Array<Int> = [];
	final events:Array<Int> = [];
	final revents:Array<Int> = [];
	final waiting:Array<Null<Op>> = [];

	override function connect(op:Op):Bool {
		var s = op.handle.socket;
		s.setBlocking(false);
		try s.connect(new sys.net.Host(op.host), op.port) catch (e:Dynamic) {
			complete(op, new Exception('connect to ${op.host}:${op.port}: $e'));
			return false;
		}
		return true;
	}

	override function exitPolled(p:Process):Bool
		return p.exitFd >= 0;

	override public function poll(seconds:Float) {
		if (asked > 0 || loop.held > 0) seconds = seconds < 0 || seconds > 0.01 ? 0.01 : seconds;
		var n = 0, closed = false;
		for (op in ops) {
			var fd = -1, ev = 0;
			if (op.kind == Exit) {
				if (op.process.exitFd >= 0) {
					fd = op.process.exitFd;
					ev = Poll.IN;
				}
			} else if (op.handle.closed) {
				closed = true;
			} else if (op.handle.polled()) {
				fd = op.handle.socket != null ? Poll.socketFd(op.handle.socket) : op.handle.fd;
				ev = op.kind == Connect || op.kind == Write ? Poll.OUT : Poll.IN;
			}
			if (ev == 0) continue;
			if (n == fds.length) {
				fds.push(0);
				events.push(0);
				revents.push(0);
				waiting.push(null);
			}
			fds[n] = fd;
			events[n] = ev;
			revents[n] = 0;
			waiting[n] = op;
			n++;
		}
		if (closed) seconds = 0;
		var ready = 0;
		if (n == 0) {
			if (seconds > 0) Sys.sleep(seconds);
		} else {
			// (interrupted by a signal: nothing ready this time)
			ready = try Poll.wait(fds, events, revents, n, seconds) catch (_:Dynamic) 0;
		}
		for (i in 0...n) {
			var op = waiting[i];
			waiting[i] = null;
			if (ready > 0 && revents[i] != 0 && op.cont != null) attempt(op);
		}
		// (a handle closed while an operation waited on it)
		if (closed) {
			var i = ops.length;
			while (i-- > 0) {
				var op = ops[i];
				if (op.kind != Exit && op.handle.closed) {
					op.error = new Exception("closed");
					done(op);
				}
			}
		}
		if (asked > 0) ask();
	}

	// readiness: the call, unless it would block after all
	function attempt(op:Op) {
		var h = op.handle;
		try {
			switch op.kind {
				case Accept:
					op.socket = h.socket.accept();
				case Connect:
					var e = h.socket.connectError();
					if (e != null) op.error = new Exception('connect to ${op.host}:${op.port}: $e');
				case Read if (h.socket == null):
					var n = NativeSys.fileRead(h.fd, op.buf, op.pos, op.len);
					if (n == NativeSys.WOULD_BLOCK) return;
					if (n < 0) op.error = new Exception("read failed") else op.result = n;
				case Read:
					op.result = try h.socket.input.readBytes(op.buf, op.pos, op.len) catch (e:haxe.io.Eof) 0;
				case Write if (h.socket == null):
					var n = NativeSys.fileWrite(h.fd, op.buf, op.pos, op.len);
					if (n == NativeSys.WOULD_BLOCK) return;
					if (n < 0) op.error = new Exception("write failed") else op.result = n;
				case Write:
					op.result = h.socket.output.writeBytes(op.buf, op.pos, op.len);
				case Exit:
					var c = op.process.poll();
					if (c >= 0) exited(op.process, c);
					return;
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
}
#else
// select(2) (sys.net.Socket.select, Eval's), where hxmc.net.Poll is not:
// sockets; pipes and exits on threads (ReadyIo). FD_SETSIZE: 1024
// descriptors. A connect or write waits for the socket's errors too.
class SelectIo extends ReadyIo {
	override function connect(op:Op):Bool {
		// (non-blocking: in progress, done once writable; Eval: done now)
		var s = op.handle.socket;
		s.setBlocking(false);
		try s.connect(new sys.net.Host(op.host), op.port) catch (e:Dynamic) {
			var m = Std.string(e);
			if (m.indexOf("progress") < 0 && m.indexOf("Blocked") < 0 && m.indexOf("would block") < 0) {
				complete(op, new Exception('connect to ${op.host}:${op.port}: $m'));
				return false;
			}
		}
		return true;
	}

	override public function poll(seconds:Float) {
		if (asked > 0 || loop.held > 0) seconds = seconds < 0 || seconds > 0.01 ? 0.01 : seconds;
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
		if (asked > 0) ask();
	}

	function attempt(op:Op) {
		var s = op.handle.socket;
		try {
			switch op.kind {
				case Accept:
					op.socket = s.accept();
				case Connect:
					try s.peer() catch (e:Dynamic) throw new Exception('connect to ${op.host}:${op.port}: refused');
				case Read:
					op.result = try s.input.readBytes(op.buf, op.pos, op.len) catch (e:haxe.io.Eof) 0;
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
}
#end

class NoIo implements Backend {
	public function new() {}

	public function submit(op:Op)
		throw new Exception("helder.async: no sockets or processes here");

	public function cancel(op:Op) {}

	public function pending():Int
		return 0;

	public function poll(seconds:Float) {}
}
