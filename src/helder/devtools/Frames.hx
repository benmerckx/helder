package helder.devtools;

#if (hxmc.dev && !macro)
import haxe.ds.Vector;

// The Frame domain: each frame's time (from the last frame's end), its work
// (from the turn's start, Hot.poll, to its end, Hot.framed), the GC bytes
// allocated in it, the collections and their seconds (GcCounters), kept in
// columns allocated once and sent as one Frame.stats notification per
// interval (or per CAP frames). A frame recorded allocates nothing; a batch
// sent counts its own garbage apart (Agent.own, agentBytes), so the frames'
// bytes are the program's.
@:allow(helder.devtools.Agent)
class Frames {
	static inline var CAP = 256;

	static var dt:Vector<Float>;
	static var work:Vector<Float>;
	static var gcBytes:Vector<Float>;
	static var gcCount:Vector<Float>;
	static var gcMs:Vector<Float>;
	static var n = 0;
	// the frames recorded since enabled (the first of a batch: count - n)
	static var count = 0;
	static var interval = 0.1;
	static var flushedAt = 0.0;
	static var turnAt = -1.0;
	static var last = -1.0;
	static var lastBytes = 0.0;
	static var lastCount = 0;
	static var lastSecs = 0.0;
	static var ownSent = 0.0;

	static function enable(ms:Float):Dynamic {
		if (dt == null) {
			dt = new Vector(CAP);
			work = new Vector(CAP);
			gcBytes = new Vector(CAP);
			gcCount = new Vector(CAP);
			gcMs = new Vector(CAP);
		}
		interval = Math.max(ms, 10) / 1000;
		if (!Agent.framing) {
			GcCounters.enable(true);
			n = 0;
			last = -1;
			turnAt = -1;
			flushedAt = Agent.now();
			ownSent = Agent.own;
			Agent.setFraming(true);
		}
		return {interval: interval * 1000, timed: GcCounters.TIMED};
	}

	static function disable():Dynamic {
		if (Agent.framing) {
			flush(Agent.now());
			Agent.setFraming(false);
			GcCounters.enable(false);
		}
		return {};
	}

	static function turn()
		turnAt = Agent.now();

	static function frame() {
		var now = Agent.now();
		var bytes = GcCounters.bytes() - Agent.own, c = GcCounters.collections(), s = GcCounters.seconds();
		if (last >= 0) {
			dt[n] = (now - last) * 1000;
			work[n] = turnAt >= last ? (now - turnAt) * 1000 : 0;
			gcBytes[n] = bytes - lastBytes;
			gcCount[n] = c - lastCount;
			gcMs[n] = (s - lastSecs) * 1000;
			n++;
			count++;
		}
		last = now;
		lastBytes = bytes;
		lastCount = c;
		lastSecs = s;
		if (n == CAP || (n > 0 && now - flushedAt >= interval)) flush(now);
	}

	// the batch, its garbage the agent's
	static function flush(now:Float) {
		flushedAt = now;
		if (n == 0) return;
		var b0 = GcCounters.bytes();
		var s = new StringBuf();
		s.add('{"jsonrpc":"2.0","method":"Frame.stats","params":{"first":');
		s.add(count - n);
		column(s, "dt", dt, 1000);
		column(s, "work", work, 1000);
		column(s, "gcBytes", gcBytes, 1);
		column(s, "gcCollections", gcCount, 1);
		column(s, "gcPauseMs", gcMs, 1000);
		s.add(',"agentBytes":');
		s.add(Math.round(Agent.own - ownSent));
		s.add("}}");
		n = 0;
		helder.dev.Hot.sendLine(s.toString());
		ownSent = Agent.own;
		Agent.own += GcCounters.bytes() - b0;
		// (the frame being recorded: its bytes from here)
		lastBytes = GcCounters.bytes() - Agent.own;
	}

	// ,"name":[v, ...] rounded to 1/scale
	static function column(s:StringBuf, name:String, v:Vector<Float>, scale:Float) {
		s.add(',"');
		s.add(name);
		s.add('":[');
		for (i in 0...n) {
			if (i > 0) s.add(",");
			var x = Math.round(v[i] * scale);
			s.add(scale == 1 ? Std.string(x) : Std.string(x / scale));
		}
		s.add("]");
	}
}
#end
