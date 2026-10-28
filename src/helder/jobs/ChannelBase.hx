package helder.jobs;

import haxe.coro.IContinuation;
import helder.async.Async;
import helder.async.Loop;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Ptr;

// What every Channel<T> is (Channel's macro makes one per T, with its
// codec): messages as IoBuffers (Wire), sent from any thread or job,
// received on the loop of the thread that made it, in order. Natively a
// queue under a lock, its sends posted to that loop; a browser's worker's
// sends go to the page, which delivers them (WebJobs). Known by id
// (Sendable: what crosses), until closed.
@:allow(helder.jobs)
class ChannelBase {
	static var nextId = 1;
	static final all = new Map<Int, ChannelBase>();
	#if target.threaded
	static final allLock = new sys.thread.Mutex();
	#end

	public final id:Int;
	// (the owner's loop; null: a stand-in in a browser's worker, its sends to the page)
	final loop:Null<Loop>;
	final queue:Array<IoBuffer> = [];
	var closed = false;
	var waiter:Null<IContinuation<Bool>>;
	#if target.threaded
	final lock = new sys.thread.Mutex();
	#end

	function new(?remote:Int) {
		if (remote != null) {
			id = remote;
			loop = null;
			return;
		}
		loop = Loop.current();
		#if target.threaded
		allLock.acquire();
		#end
		id = nextId++;
		all.set(id, this);
		#if target.threaded
		allLock.release();
		#end
	}

	// (the channel of that id here, null when there is none: a worker's instance, or closed)
	static function find(id:Int):Null<ChannelBase> {
		#if target.threaded
		allLock.acquire();
		#end
		var c = all.get(id);
		#if target.threaded
		allLock.release();
		#end
		return c;
	}

	// whether it was closed (sends then throw; receives end once the queue is empty)
	public function isClosed():Bool
		return closed;

	// no more messages: receive returns null once the ones sent are received
	public function close() {
		#if (hxmc.target == "wasm32-wasi")
		if (loop == null) {
			JobsHost.close(id);
			return;
		}
		#end
		#if target.threaded
		lock.acquire();
		#end
		closed = true;
		#if target.threaded
		lock.release();
		allLock.acquire();
		#end
		all.remove(id);
		#if target.threaded
		allLock.release();
		#end
		loop.post(wake);
	}

	// (a message, from any thread)
	function push(b:IoBuffer) {
		#if (hxmc.target == "wasm32-wasi")
		if (loop == null) {
			JobsHost.send(id, b.ptr, b.length);
			b.free();
			return;
		}
		#end
		#if target.threaded
		lock.acquire();
		#end
		var shut = closed;
		if (!shut) queue.push(b);
		#if target.threaded
		lock.release();
		#end
		if (shut) {
			b.free();
			throw new JobError(-1, "send on a closed channel");
		}
		loop.post(wake);
	}

	// (the next message, null once closed and empty: the owner's thread only)
	@:coroutine function take():Null<IoBuffer> {
		if (loop == null) throw new JobError(-1, "a channel is received from on the thread that made it");
		while (true) {
			#if target.threaded
			lock.acquire();
			#end
			var b = queue.length > 0 ? queue.shift() : null;
			var shut = closed;
			#if target.threaded
			lock.release();
			#end
			if (b != null) return b;
			if (shut) return null;
			var l = loop;
			var self = this;
			Async.suspendCancellable(cont -> {
				self.waiter = cont;
				l.hold();
				return _ -> {
					self.waiter = null;
					l.release();
				};
			});
		}
	}

	// (on the owner's loop: a waiting receive goes on)
	function wake() {
		var w = waiter;
		if (w == null) return;
		waiter = null;
		loop.release();
		w.resume(true, null);
	}

	// (the page: a worker's message, a close)
	static function deliver(id:Int, b:IoBuffer) {
		var c = find(id);
		if (c == null) {
			if (!(cast b : Ptr).isNull()) b.free();
			return;
		}
		c.push(b);
	}

	static function closedBy(id:Int) {
		var c = find(id);
		if (c != null) c.close();
	}
}
