package jobs;

import haxe.exceptions.CancellationException;
import haxe.io.Bytes;
import helder.async.*;
import helder.jobs.*;
import hxmc.unsafe.*;
import helder.test.Test;

// helder.jobs: the pool natively, workers under node on wasm32-wasi
// (`bun run helder test tests/jobs`). The sendable check's rejections are the jobs
// lane's (tests/jobs/reject).
function tests() {
	describe("jobs", () -> {
		test("a GC-free job: its input moved in, its output back", async(() -> {
			var b = IoBuffer.alloc(5);
			for (i in 0...5)
				b.set(i, i * 10);
			var out = Jobs.run(JobsWork.invert, b);
			equals([for (i in 0...out.length) out.get(i)], [255, 245, 235, 225, 215]);
			out.free();
		}));
		test("a GC job: values copied in and out", async(() -> {
			equals(Jobs.run(JobsWork.words, "one two three"), 3);
			var r = Jobs.run(JobsWork.summary, {name: "n", values: [1.5, 2.5], flag: true, count: null});
			equals(r, {total: 4.0, label: "n:2", nothing: null});
			equals(Jobs.run(JobsWork.answer), 42);
			Jobs.run(JobsWork.nothing, 1);
		}));
		test("Bytes are copied, an IoBuffer moved", async(() -> {
			var b = Bytes.ofString("abc");
			var back = Jobs.run(JobsWork.upper, b);
			equals(back.toString(), "ABC");
			equals(b.toString(), "abc");
			var io = IoBuffer.ofBytes(Bytes.ofString("xyz"));
			var moved = Jobs.run(JobsWork.reverse, {buffer: io, tag: 7});
			equals(moved.getBytes(0, moved.length).toString(), "zyx7");
			moved.free();
		}));
		test("a struct crosses as its bytes", async(() -> {
			approx(Jobs.run(JobsWork.length, new JobsVec(3, 4)), 5);
			var v = Jobs.run(JobsWork.half, new JobsVec(3, 4));
			approx(v.x, 1.5);
			approx(v.y, 2);
		}));
		test("on workers, several at once", async(() -> {
			var rs = Async.scope(task -> Async.all([for (i in 0...8) task.async(_ -> Jobs.run(JobsWork.where, i))]));
			equals([for (r in rs) r.i], [for (i in 0...8) i]);
			for (r in rs)
				assert(r.worker, 'job ${r.i} ran on a worker');
		}));
		test("the loop runs while a job does", async(() -> {
			var log = [];
			Async.scope(task -> {
				var j = task.async(_ -> try Jobs.run(JobsWork.spin) catch (e:CancellationException) {
					log.push("job cancelled");
					throw e;
				});
				Async.delay(0.02);
				log.push("timer");
				j.cancel();
			});
			equals(log, ["timer", "job cancelled"]);
		}));
		test("cancelled: the task resumes at once, the job sees it (natively) or its worker ends (wasm)", async(() -> {
			JobsWork.sawCancel = 0;
			var t0 = haxe.Timer.stamp();
			var e = throwsAsync(() -> Async.timeout(0.05, _ -> Jobs.run(JobsWork.spin)));
			assert(e is Async.TimeoutException, "a TimeoutException");
			assert(haxe.Timer.stamp() - t0 < 1, "resumed at the timeout");
			#if (hxmc.target != "wasm32-wasi")
			var waited = 0;
			while (JobsWork.sawCancel == 0 && waited++ < 100)
				Async.delay(0.01);
			equals(JobsWork.sawCancel, 1);
			#end
			// (and the next job runs: natively the thread is free, in a browser a new worker)
			equals(Jobs.run(JobsWork.words, "a b"), 2);
		}));
		test("errors: a GC-free job's code, a GC job's exception", async(() -> {
			var e:JobError = throwsAsync(() -> Jobs.run(JobsWork.refuse, IoBuffer.alloc(1)));
			equals(e.code, -5);
			var g:JobError = throwsAsync(() -> Jobs.run(JobsWork.boom, 3));
			equals(g.code, -1);
			equals(g.message, "boom 3");
		}));
		test("a channel: a job's values in order, then its close", async(() -> {
			var ch = new Channel<{i:Int, s:String}>();
			var got = Async.scope(task -> {
				task.async(_ -> Jobs.run(JobsWork.count, {n: 5, out: ch}));
				var got = [], v;
				while ((v = ch.receive()) != null)
					got.push(v.s + v.i);
				got;
			});
			equals(got, ["v0", "v1", "v2", "v3", "v4"]);
			assert(ch.isClosed());
		}));
		test("a channel on one thread, and a send once closed", async(() -> {
			var ch = new Channel<Int>();
			ch.send(1);
			ch.send(2);
			ch.close();
			equals(ch.receive(), 1);
			equals(ch.receive(), 2);
			equals(ch.receive(), null);
			var e:JobError = throws(() -> ch.send(3));
			equals(e.message, "send on a closed channel");
		}));
		test("without workers: on the loop, the same results", async(() -> {
			var was = Jobs.workers;
			Jobs.workers = 0;
			var r = Jobs.run(JobsWork.where, 3);
			var b = IoBuffer.alloc(1);
			var out = Jobs.run(JobsWork.invert, b);
			Jobs.workers = was;
			equals(r.i, 3);
			assert(!r.worker, "on the loop");
			equals(out.get(0), 255);
			out.free();
		}));
	});
}

// (the jobs: a job is a static function another module can name)
class JobsWork {
	public static var sawCancel = 0;

	@:hxmc.unsafe @:hxmc.callback public static function invert(job:Job):Int {
		var n = job.input.length, src = job.input.ptr, out = job.output(n);
		if (out.isNull()) return -1;
		for (i in 0...n)
			Mem.setI8(out, i, 255 - Mem.getU8(src, i));
		return 0;
	}

	@:hxmc.unsafe @:hxmc.callback public static function refuse(job:Job):Int
		return -5;

	// (until cancelled, a few seconds at most)
	@:hxmc.unsafe @:hxmc.callback public static function spin(job:Job):Int {
		var s = 0;
		for (i in 0...20000) {
			if (job.cancelled) {
				sawCancel = 1;
				return -2;
			}
			for (k in 0...100000)
				s = (s * 31 + k) & 0xFFFFFF;
		}
		return s & 0;
	}

	public static function words(s:String):Int
		return s.split(" ").length;

	public static function summary(p:{name:String, values:Array<Float>, flag:Bool, count:Null<Int>}):{total:Float, label:String, nothing:Null<Int>} {
		var t = 0.0;
		for (v in p.values)
			t += v;
		return {total: p.flag ? t : -1, label: p.name + ":" + p.values.length, nothing: p.count};
	}

	public static function answer():Int
		return 42;

	public static function nothing(x:Int):Void {}

	public static function upper(b:Bytes):Bytes {
		var s = b.toString().toUpperCase();
		// (the caller's bytes: a copy here)
		b.set(0, "Q".code);
		return Bytes.ofString(s);
	}

	public static function reverse(p:{buffer:IoBuffer, tag:Int}):IoBuffer {
		var n = p.buffer.length, out = IoBuffer.alloc(n + 1);
		for (i in 0...n)
			out.set(i, p.buffer.get(n - 1 - i));
		out.set(n, "0".code + p.tag);
		p.buffer.free();
		return out;
	}

	public static function length(v:JobsVec):Float
		return Math.sqrt(v.x * v.x + v.y * v.y);

	public static function half(v:JobsVec):JobsVec
		return new JobsVec(v.x / 2, v.y / 2);

	public static function where(i:Int):{i:Int, worker:Bool}
		return {i: i, worker: Jobs.onWorker()};

	public static function boom(x:Int):Int
		throw "boom " + x;

	public static function count(p:{n:Int, out:Channel<{i:Int, s:String}>}):Void {
		for (i in 0...p.n)
			p.out.send({i: i, s: "v"});
		p.out.close();
	}
}

@:hxmc.struct class JobsVec {
	public var x:Float;
	public var y:Float;

	public inline function new(x:Float, y:Float) {
		this.x = x;
		this.y = y;
	}
}
