package helder.async;

import haxe.io.Bytes;
import helder.async.Io;
import helder.async.Stream;
import sys.net.Socket as NetSocket;

// A TCP connection on the loop: reads and writes suspend instead of blocking.
//
//   var s = Socket.connect("127.0.0.1", 6000);
//   s.writeString("hello\n");
//   var line = new Reader(s).readLine();
//   s.close();
class Socket implements Source implements Sink {
	public final handle:Handle;

	function new(s:NetSocket) {
		s.setBlocking(false);
		handle = new Handle(s);
	}

	@:coroutine public static function connect(host:String, port:Int):Socket {
		var s = new NetSocket();
		var sock = new Socket(s);
		try new Op(Connect, sock.handle, null, 0, 0, host, port).run() catch (e:haxe.Exception) {
			s.close();
			throw e;
		}
		return sock;
	}

	// at most len bytes into b at pos, once some came; 0 at the end
	@:coroutine public function read(b:Bytes, pos:Int, len:Int):Int
		return new Op(Read, handle, b, pos, len).run().result;

	@:coroutine public function write(b:Bytes, pos:Int, len:Int):Void {
		while (len > 0) {
			var n = new Op(Write, handle, b, pos, len).run().result;
			pos += n;
			len -= n;
		}
	}

	@:coroutine public function writeString(s:String):Void {
		var b = Bytes.ofString(s);
		write(b, 0, b.length);
	}

	// the other side's address
	public function peer():{host:String, port:Int} {
		var p = handle.socket.peer();
		return {host: p.host.toString(), port: p.port};
	}

	// no more writes (the other side reads its end)
	public function shutdown()
		try handle.socket.shutdown(false, true) catch (_:Dynamic) {};

	public function close() {
		if (handle.closed) return;
		handle.closed = true;
		handle.socket.close();
	}
}
