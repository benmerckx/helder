package helder.async;

import helder.async.Io;
import sys.net.Socket as NetSocket;

// A listening TCP socket: accept suspends until a connection comes.
//
//   var server = Server.listen("127.0.0.1", 8080);   // port 0: any free one, server.port
//   while (true) { var s = server.accept(); task.async(_ -> serve(s)); }
class Server {
	public final handle:Handle;
	public final port:Int;

	function new(s:NetSocket) {
		handle = new Handle(s);
		port = s.host().port;
	}

	public static function listen(host = "127.0.0.1", port = 0, backlog = 128):Server {
		var s = new NetSocket();
		s.bind(new sys.net.Host(host), port);
		s.listen(backlog);
		s.setBlocking(false);
		return new Server(s);
	}

	@:coroutine public function accept():Socket
		return @:privateAccess new Socket(new Op(Accept, handle).run().socket);

	public function close() {
		if (handle.closed) return;
		handle.closed = true;
		handle.socket.close();
	}
}
