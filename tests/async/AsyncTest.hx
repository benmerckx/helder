import haxe.Exception;
import haxe.exceptions.CancellationException;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.Async.TimeoutException;
import helder.async.http.Http;
import helder.async.http.WebSocket;

// helder.async on Eval and natively: `haxe -cp src -cp tests/async -main
// AsyncTest --interp`; prints "ok" and the number of checks, exits 1 on a
// failure. The loop, tasks, cancellation, errors, timers, then TCP,
// processes, the watcher, HTTP and WebSocket.
class AsyncTest {
	static var checks = 0;
	static var failures = 0;

	static function eq<T>(got:T, want:T, what:String) {
		checks++;
		if (got != want) {
			failures++;
			Sys.println('FAIL $what: got $got, want $want');
		}
	}

	static function ok(c:Bool, what:String)
		eq(c, true, what);

	static function main() {
		if (!sys.FileSystem.exists("bin/async")) sys.FileSystem.createDirectory("bin/async");
		loop();
		tasks();
		cancellation();
		errors();
		timers();
		tcp();
		process();
		watch();
		http();
		Sys.println(failures == 0 ? 'ok ($checks checks)' : '$failures of $checks checks failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	// the loop without coroutines: haxe.coro's scheduler, turn, post
	static function loop() {
		var l = Loop.current();
		ok(Loop.current() == l, "one loop per thread");
		var order = [];
		l.schedule(20, new Fn(l, () -> order.push("b")));
		l.schedule(10, new Fn(l, () -> order.push("a")));
		var t = l.schedule(15, new Fn(l, () -> order.push("cancelled")));
		t.close();
		ok(l.alive(), "alive with timers");
		var turns = 0;
		while (l.turn(-1)) turns++;
		eq(order.join(","), "a,b", "timers in order, a closed one left out");
		ok(!l.alive(), "nothing left");
		eq(l.turn(0), false, "turn(0) when idle");
		// (a turn waits at most what it is given)
		l.schedule(200, new Fn(l, () -> order.push("late")));
		var t0 = haxe.Timer.stamp();
		l.turn(0.02);
		var dt = haxe.Timer.stamp() - t0;
		ok(dt < 0.15 && order.length == 2, 'turn(0.02) returns early: $dt');
		l.runUntil(() -> order.length == 3);
		eq(order[2], "late", "runUntil");
		#if target.threaded
		var got = 0;
		l.hold();
		sys.thread.Thread.create(() -> l.post(() -> {
			got = 42;
			l.release();
		}));
		l.runUntil(() -> got != 0);
		eq(got, 42, "post from another thread");
		#end
	}

	static function tasks() {
		eq(Async.run(_ -> 7), 7, "run returns the body's result");
		var log = [];
		var r = Async.run(task -> {
			var a = task.async(_ -> {
				Async.delay(0.03);
				log.push("a");
				1;
			});
			var b = task.async(_ -> {
				Async.delay(0.01);
				log.push("b");
				2;
			});
			log.push("main");
			a.await() + b.await();
		});
		eq(r, 3, "await two children");
		eq(log.join(","), "main,b,a", "children run concurrently");
		var all = Async.run(task -> Async.all([for (i in 0...5) task.async(_ -> {
			Async.delay(0.01 * (5 - i));
			i * i;
		})]));
		eq(all.join(","), "0,1,4,9,16", "all, in order");
		// (a parent is done once its children are)
		var childDone = false;
		Async.run(task -> {
			task.async(_ -> {
				Async.delay(0.02);
				childDone = true;
			});
			0;
		});
		ok(childDone, "run waits for the children it did not await");
		var n = Async.run(task -> {
			var count = 0;
			for (i in 0...3)
				task.async(_ -> {
					Async.delay(0.01);
					count++;
				});
			task.awaitChildren();
			count;
		});
		eq(n, 3, "awaitChildren");
		var nested = Async.run(_ -> Async.scope(s -> {
			var x = s.async(_ -> {
				Async.yield();
				5;
			});
			x.await() * 2;
		}));
		eq(nested, 10, "scope");
		// (a launched task runs when the loop turns)
		var t = Async.launch(_ -> {
			Async.delay(0.01);
			"launched";
		});
		ok(t.isActive(), "launch: active");
		Loop.current().runUntil(() -> !t.isActive());
		eq(t.get(), "launched", "launch: its result");
		eq(Async.run(_ -> Async.context().get(Node.key) != null), true, "the context has the task");
	}

	static function cancellation() {
		var log = [];
		Async.run(task -> {
			var a = task.async(_ -> {
				try Async.delay(10) catch (e:CancellationException) {
					log.push("a cancelled");
					throw e;
				}
				log.push("a not cancelled");
			});
			Async.delay(0.01);
			a.cancel();
			try a.await() catch (e:CancellationException) log.push("await threw");
		});
		eq(log.join(","), "a cancelled,await threw", "a cancelled child");
		// (parent to children, grandchildren)
		var deep = 0;
		var t0 = haxe.Timer.stamp();
		var root = Async.launch(task -> {
			task.async(c -> {
				c.async(_ -> try Async.delay(10) catch (e:CancellationException) {
					deep++;
					throw e;
				});
				try Async.delay(10) catch (e:CancellationException) {
					deep++;
					throw e;
				}
			});
			Async.delay(10);
		});
		var l = Loop.current();
		l.turn(0);
		root.cancel();
		l.runUntil(() -> !root.isActive());
		eq(deep, 2, "cancellation reaches children and grandchildren");
		ok(root.getError() is CancellationException, "the root's error: a cancellation");
		ok(haxe.Timer.stamp() - t0 < 1, "cancelled timers do not keep the loop");
		ok(!l.alive(), "nothing left after a cancellation");
		// (a child started by a cancelled parent never runs)
		var ran = false;
		var p = Async.launch(task -> {
			task.cancel();
			task.async(_ -> ran = true);
			Async.delay(1);
		});
		l.runUntil(() -> !p.isActive());
		ok(!ran, "no child starts in a cancelled task");
		// (cancelling a child leaves the parent alone)
		eq(Async.run(task -> {
			var c = task.async(_ -> Async.delay(10));
			Async.yield();
			c.cancel();
			Async.delay(0.01);
			"parent fine";
		}), "parent fine", "a child's cancellation does not cancel its parent");
	}

	static function errors() {
		var e = try {
			Async.run(_ -> {
				Async.delay(0.01);
				throw new Exception("boom");
			});
			null;
		} catch (e:Exception) e.message;
		eq(e, "boom", "run throws the body's error");
		var siblingCancelled = false;
		var e2 = try {
			Async.run(task -> {
				task.async(_ -> try Async.delay(10) catch (c:CancellationException) {
					siblingCancelled = true;
					throw c;
				});
				task.async(_ -> {
					Async.delay(0.01);
					throw new Exception("child failed");
				});
				Async.delay(10);
				"not here";
			});
		} catch (e:Exception) e.message;
		eq(e2, "child failed", "a child's error becomes the parent's");
		ok(siblingCancelled, "and cancels its siblings");
		// (scope: the error is the awaiter's, to catch)
		var caught = Async.run(_ -> {
			var r = try Async.scope(s -> {
				s.async(_ -> throw new Exception("inner"));
				Async.delay(10);
				"no";
			}) catch (e:Exception) "caught " + e.message;
			r;
		});
		eq(caught, "caught inner", "a scope's error caught by its caller");
		// (an awaited child's error still fails the parent: structured concurrency)
		var inner = "";
		var outer = try {
			Async.run(task -> {
				var t = task.async(_ -> {
					throw new Exception("x");
					0;
				});
				try t.await() catch (e:Exception) inner = e.message;
				Async.delay(1);
			});
			"";
		} catch (e:Exception) e.message;
		eq(inner + outer, "xx", "await throws the child's error, and so does its parent");
		// (tests/async/rep/CatchThenCall.hx: a caught error not thrown again by
		// the next call of helder.async's that returns at once)
		eq(Async.run(_ -> {
			try Async.timeout(0.01, _ -> Async.delay(1)) catch (e:TimeoutException) {}
			Async.context();
			Async.suspend(c -> c.resume(1, null));
			"not thrown again";
		}), "not thrown again", "a caught error stays caught");
	}

	static function timers() {
		var t0 = haxe.Timer.stamp();
		Async.run(_ -> Async.delay(0.05));
		var dt = haxe.Timer.stamp() - t0;
		ok(dt >= 0.045 && dt < 0.5, 'delay(0.05): $dt');
		var r = Async.run(_ -> try Async.timeout(0.02, _ -> {
			Async.delay(10);
			"slow";
		}) catch (e:TimeoutException) "timed out");
		eq(r, "timed out", "timeout");
		eq(Async.run(_ -> Async.timeout(1, _ -> {
			Async.delay(0.01);
			"fast";
		})), "fast", "within the timeout");
		ok(!Loop.current().alive(), "the timeout's timer closed");
		// (yield lets the others run)
		var log = [];
		Async.run(task -> {
			task.async(_ -> for (i in 0...3) {
				log.push("a" + i);
				Async.yield();
			});
			task.async(_ -> for (i in 0...3) {
				log.push("b" + i);
				Async.yield();
			});
			0;
		});
		eq(log.join(","), "a0,b0,a1,b1,a2,b2", "yield interleaves");
		// (a lock: in order of arrival)
		var order = [];
		Async.run(task -> {
			var lock = new Lock();
			for (i in 0...3)
				task.async(_ -> {
					lock.acquire();
					order.push(i);
					Async.delay(0.005);
					order.push(i);
					lock.release();
				});
			0;
		});
		eq(order.join(""), "001122", "lock");
	}

	static function tcp() {
		var got = Async.run(task -> {
			var server = Server.listen("127.0.0.1", 0);
			ok(server.port > 0, "listen on a free port");
			task.async(_ -> {
				for (i in 0...2) {
					var c = server.accept();
					task.async(_ -> {
						var r = new Reader(c);
						var line;
						while ((line = r.readLine()) != null)
							c.writeString(line.toUpperCase() + "\n");
						c.close();
					});
				}
				server.close();
			});
			var a = Socket.connect("127.0.0.1", server.port);
			var b = Socket.connect("127.0.0.1", server.port);
			var ra = new Reader(a), rb = new Reader(b);
			a.writeString("hello\n");
			b.writeString("world\r\n");
			var out = [ra.readLine(), rb.readLine()];
			// (large writes: both directions at once)
			var big = Bytes.alloc(1 << 20);
			for (i in 0...big.length)
				big.set(i, 97 + i % 26);
			var sent = task.async(_ -> {
				a.write(big, 0, big.length);
				a.writeString("\n");
			});
			var line = ra.readLine();
			sent.await();
			out.push(Std.string(line.length));
			out.push(line.substr(0, 3));
			a.shutdown();
			eq(ra.readLine(), null, "end of the stream");
			a.close();
			b.close();
			out.join(" ");
		});
		eq(got, "HELLO WORLD 1048576 ABC", "TCP: two clients, a megabyte each way");
		var refused = try {
			Async.run(_ -> Socket.connect("127.0.0.1", 1));
			"connected";
		} catch (e:Exception) "refused";
		eq(refused, "refused", "connect refused");
		// (a read cancelled: the socket stays usable)
		var after = Async.run(task -> {
			var server = Server.listen("127.0.0.1", 0);
			var accepted = task.async(_ -> server.accept());
			var c = Socket.connect("127.0.0.1", server.port);
			var s = accepted.await();
			try Async.timeout(0.02, _ -> c.read(Bytes.alloc(8), 0, 8)) catch (e:TimeoutException) {}
			s.writeString("late\n");
			var l = new Reader(c).readLine();
			c.close();
			s.close();
			server.close();
			l;
		});
		eq(after, "late", "a read cancelled by a timeout, then another");
		ok(!Loop.current().alive(), "TCP: nothing left");
	}

	static function process() {
		var got = Async.run(task -> {
			var p = new Process("sh", ["-c", "echo one; echo err >&2; sleep 0.05; echo two; read x; echo got $x; exit 3"]);
			var err = task.async(_ -> new Reader(p.stderr).readAll().toString());
			var out = new Reader(p.stdout);
			var lines = [out.readLine(), out.readLine()];
			var input = Bytes.ofString("input\n");
			p.stdin.write(input, 0, input.length);
			p.closeStdin();
			lines.push(out.readLine());
			eq(out.readLine(), null, "the end of stdout");
			var code = p.wait();
			p.close();
			lines.join(",") + " " + StringTools.trim(err.await()) + " " + code;
		});
		eq(got, "one,two,got input err 3", "a process: stdout, stderr, stdin, its exit code");
		// (many lines, and two processes at once)
		var counts = Async.run(task -> Async.all([for (n in [2000, 3000]) task.async(_ -> {
			var p = new Process("sh", ["-c", 'i=0; while [ $$i -lt $n ]; do echo line $$i; i=$$((i+1)); done']);
			var r = new Reader(p.stdout), k = 0;
			while (r.readLine() != null)
				k++;
			p.wait();
			p.close();
			k;
		})]));
		eq(counts.join(","), "2000,3000", "two processes' output at once");
		var killed = Async.run(_ -> {
			var p = new Process("sleep", ["10"]);
			Async.delay(0.02);
			p.kill();
			var c = p.wait();
			p.close();
			c;
		});
		ok(killed != 0, 'a killed process: $killed');
		ok(!Loop.current().alive(), "processes: nothing left");
	}

	static function watch() {
		var dir = "bin/async/watched";
		rmrf(dir);
		sys.FileSystem.createDirectory(dir);
		sys.FileSystem.createDirectory('$dir/sub');
		sys.io.File.saveContent('$dir/a.txt', "a");
		sys.io.File.saveContent('$dir/sub/b.txt', "b");
		sys.io.File.saveContent('$dir/sub/skip.tmp', "x");
		var batches = Async.run(task -> {
			var w = new PollWatcher([dir], 0.02, 0.06, p -> StringTools.endsWith(p, ".tmp"));
			task.async(_ -> {
				Async.delay(0.05);
				sys.io.File.saveContent('$dir/a.txt', "aa");
				Async.delay(0.02);
				sys.io.File.saveContent('$dir/sub/b.txt', "bbb");
				sys.io.File.saveContent('$dir/sub/skip.tmp', "changed");
				Async.delay(0.3);
				sys.io.File.saveContent('$dir/sub/c.txt', "new");
				sys.FileSystem.deleteFile('$dir/a.txt');
			});
			var first = w.next();
			var second = w.next();
			w.close();
			[first.join(" "), second.join(" ")];
		});
		eq(batches[0], '$dir/a.txt $dir/sub/b.txt', "a debounced batch, recursive, ignored paths left out");
		eq(batches[1], '$dir/a.txt $dir/sub/c.txt', "added and removed");
	}

	static function http() {
		var root = "bin/async/www";
		rmrf(root);
		sys.FileSystem.createDirectory(root);
		sys.io.File.saveContent('$root/index.html', "<h1>hi</h1>");
		sys.io.File.saveContent('$root/app.js', "x()");
		var got = Async.run(task -> {
			var server = Server.listen("127.0.0.1", 0);
			var serving = task.async(_ -> Http.serve(server, req -> {
				if (req.path == "/ws") {
					var ws = WebSocket.upgrade(req);
					var m;
					while ((m = ws.receive()) != null)
						ws.send("echo " + m);
					return null;
				}
				if (req.path == "/fail") throw new Exception("handler failed");
				if (req.method == "POST") return Response.text("posted " + req.body.toString());
				return Http.file(root, req.path) ?? Response.text("not found", 404);
			}));
			var c = Socket.connect("127.0.0.1", server.port);
			var r = new Reader(c);
			// (keep-alive: three requests on one connection)
			c.writeString("GET / HTTP/1.1\r\nhost: x\r\n\r\nGET /app.js HTTP/1.1\r\nhost: x\r\n\r\nPOST /p HTTP/1.1\r\ncontent-length: 3\r\n\r\nabc");
			var out = [];
			for (i in 0...3) {
				var res = readResponse(r);
				out.push(res.status + " " + res.type + " " + res.body);
			}
			c.writeString("GET /missing HTTP/1.1\r\nconnection: close\r\n\r\n");
			out.push("" + readResponse(r).status);
			eq(r.readLine(), null, "connection: close");
			c.close();
			// (an error in the handler: a 500, the server goes on)
			var c2 = Socket.connect("127.0.0.1", server.port);
			c2.writeString("GET /fail HTTP/1.1\r\n\r\n");
			out.push("" + readResponse(new Reader(c2)).status);
			c2.close();
			var ws = WebSocket.connect("127.0.0.1", server.port, "/ws");
			ws.send("hello");
			out.push(ws.receive());
			var long = StringTools.lpad("", "x", 70000);
			ws.send(long);
			out.push(Std.string(ws.receive().length));
			ws.ping();
			ws.send("after ping");
			out.push(ws.receive());
			ws.close();
			eq(ws.receive(), null, "closed");
			serving.cancel();
			server.close();
			out.join("|");
		});
		eq(got, "200 text/html; charset=utf-8 <h1>hi</h1>|200 text/javascript; charset=utf-8 x()|200 text/plain; charset=utf-8 posted abc|404|500|echo hello|70005|echo after ping", "HTTP and WebSocket");
	}

	@:coroutine static function readResponse(r:Reader):{status:Int, type:String, body:String} {
		var status = Std.parseInt(r.readLine().split(" ")[1]);
		var headers = new Map<String, String>();
		while (true) {
			var h = r.readLine();
			if (h == "") break;
			var i = h.indexOf(":");
			headers.set(h.substr(0, i).toLowerCase(), StringTools.trim(h.substr(i + 1)));
		}
		var n = Std.parseInt(headers.get("content-length"));
		return {status: status, type: headers.get("content-type"), body: r.readBytes(n).toString()};
	}

	static function rmrf(path:String) {
		if (!sys.FileSystem.exists(path)) return;
		if (sys.FileSystem.isDirectory(path)) {
			for (f in sys.FileSystem.readDirectory(path))
				rmrf('$path/$f');
			sys.FileSystem.deleteDirectory(path);
		} else sys.FileSystem.deleteFile(path);
	}
}

// a function as a continuation, on a loop (the scheduler's tests)
class Fn implements haxe.coro.IContinuation<Any> {
	public var context(get, never):haxe.coro.context.Context;

	final ctx:haxe.coro.context.Context;
	final f:Void->Void;

	public function new(l:Loop, f) {
		ctx = l.context();
		this.f = f;
	}

	function get_context()
		return ctx;

	public function resume(_:Any, _:Exception)
		f();
}
