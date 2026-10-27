import helder.scoped.*;

@:build(helder.scoped.Struct.build())
abstract Vec2(Addr) {
	var x:Float;
	var y:Float;
}

@:build(helder.scoped.Value.build())
class V3 {
	var x:Float;
	var y:Float;
	var z:Float;

	public inline function add(o:V3):V3
		return new V3(x + o.x, y + o.y, z + o.z);

	public inline function scale(k:Float):V3
		return new V3(x * k, y * k, z * k);
}

@:build(helder.scoped.Value.build())
class Tagged {
	var at:V3;
	var id:Int;
	var on:Bool;
}

@:build(helder.scoped.Struct.build())
abstract Body(Addr) {
	var pos:V3;
	var tag:Tagged;
	var mass:Float;
}

@:build(helder.scoped.Struct.build())
abstract Particle(Addr) {
	var pos:Vec2;
	var life:Int;
	var alive:Bool;
	var tag:U8;
}

// helder.scoped on any target: `haxe -cp src -cp tests/scoped
// -main ScopedTest --macro helder.scoped.Check.enable() <target>`; prints "ok" and
// the number of checks, exits 1 on a failure.
// (a recursive typedef: the checker follows it twice, then stops)
typedef Tree = {name:String, children:Array<Tree>};

@:build(helder.scoped.Scoped.build())
class ScopedTest {
	static var checks = 0;
	static var failures = 0;

	static function eq<T>(got:T, want:T, what:String) {
		checks++;
		if (got != want) {
			failures++;
			println('FAIL $what: got $got, want $want');
		}
	}

	static function println(s:String) {
		#if js
		js.Syntax.code("console.log({0})", s);
		#elseif sys
		Sys.println(s);
		#else
		trace(s);
		#end
	}

	static function exit(code:Int) {
		#if js
		js.Syntax.code("process.exit({0})", code);
		#elseif sys
		Sys.exit(code);
		#end
	}

	static function fail(what:String) {
		failures++;
		println('FAIL $what: no exception');
	}

	static function throws(f:() -> Void, what:String) {
		checks++;
		try {
			f();
			failures++;
			println('FAIL $what: no exception');
		} catch (e:Memory.ScopedError) {}
	}

	static function main() {
		layout();
		throws(() -> Scope.slice(Int, 1), "allocating outside any scope");
		scalars();
		structs();
		grows();
		strings();
		values();
		bytes();
		scopes();
		#if (target.threaded && (target.name == "hxmc" || scoped_threads))
		threads();
		#end
		println(failures == 0 ? 'ok $checks' : '$failures of $checks failed');
		if (failures != 0)
			exit(1);
	}

	static function layout() {
		eq(Vec2.SIZE, 16, "Vec2.SIZE");
		eq(Vec2.ALIGN, 8, "Vec2.ALIGN");
		// pos 0..15, life 16..19, alive 20, tag 21, padded to 24
		eq(Particle.SIZE, 24, "Particle.SIZE");
		eq(Scope.size(Int), 4, "size of Int");
		var tree:Tree = {name: "root", children: [{name: "leaf", children: []}]};
		eq(tree.children.length, 1, "a recursive typedef checked");
	}

	@:scoped static function scalars() {
		// (array comprehensions: their loops' values, not iteration scopes)
		eq([for (i in 0...3) i * 2].join(","), "0,2,4", "a comprehension");
		eq([for (i in 0...3) for (j in 0...2) if (j == 1) i * 10 + j].join(","), "1,11,21", "a nested comprehension");
		var a = Scope.slice(Int, 10);
		eq(a.length, 10, "length");
		eq(a[3], 0, "zeroed");
		for (i in 0...a.length)
			a[i] = i * i;
		var sum = 0;
		for (v in a)
			sum += v;
		eq(sum, 285, "Int iterator");
		var f = Scope.slice(Float, 3);
		f[1] = 2.5;
		eq(f[1] * 2, 5.0, "Float");
		var b = Scope.slice(Bool, 2);
		b[1] = true;
		eq(b[0], false, "Bool 0");
		eq(b[1], true, "Bool 1");
		var u = Scope.slice(U8, 4);
		u[0] = 255;
		u[1] = 256;
		eq((u[0] : Int), 255, "U8 255");
		eq((u[1] : Int), 0, "U8 wraps");
		var s = a.sub(2, 3);
		eq(s[0], 4, "sub");
		s[0] = 40;
		eq(a[2], 40, "sub views the same memory");
		var r = a.ref(9);
		r.set(-1);
		eq(a[9], -1, "Ref.set");
		eq(r.get(), -1, "Ref.get");
		checks += 3;
		try {
			a[10];
			fail("index past the end");
		} catch (e:Memory.ScopedError) {}
		try {
			a[-1];
			fail("negative index");
		} catch (e:Memory.ScopedError) {}
		try {
			a.sub(8, 3);
			fail("sub past the end");
		} catch (e:Memory.ScopedError) {}
	}

	@:scoped static function structs() {
		var ps = Scope.slice(Particle, 100);
		for (i in 0...ps.length) {
			var p = ps[i];
			p.pos.x = i;
			p.pos.y = i * 2;
			p.life = 100 - i;
			p.alive = i % 2 == 0;
			p.tag = i;
		}
		eq(ps[7].pos.y, 14.0, "nested struct field");
		eq(ps[7].life, 93, "Int field");
		eq(ps[7].alive, false, "Bool field");
		eq((ps[99].tag : Int), 99, "U8 field");
		var alive = 0;
		for (p in ps)
			if (p.alive)
				alive++;
		eq(alive, 50, "struct iterator");
		var q = new Particle();
		q.pos.x = 5;
		q.life = 1;
		ps[0] = q;
		eq(ps[0].pos.x, 5.0, "struct copied in");
		q.pos.x = 6;
		eq(ps[0].pos.x, 5.0, "a copy, not a reference");
		var v = new Vec2();
		v.x = 9;
		ps[1].pos = v;
		eq(ps[1].pos.x, 9.0, "struct field assigned by copy");
		var c = new Vec2();
		c.copyFrom(ps[1].pos);
		eq(c.x, 9.0, "copyFrom");
	}

	@:scoped static function grows() {
		var g = Scope.grow(Int);
		g.push(1);
		var first = g.ref(0);
		for (i in 1...10000)
			g.push(i + 1);
		eq(g.length, 10000, "Grow length");
		eq(first.get(), 1, "a reference survives growth");
		eq(g[9999], 10000, "Grow index");
		var sum = 0.0;
		for (v in g)
			sum += v;
		eq(sum, 50005000.0, "Grow iterator");
		var s = g.slice();
		eq(s[42], 43, "Grow.slice");
		var vs = Scope.grow(Vec2);
		for (i in 0...50) {
			var v = vs.next();
			v.x = i;
		}
		eq(vs[49].x, 49.0, "Grow of structs");
		g.truncate(2);
		eq(g.length, 2, "truncate");
		var w = Scope.grow(Int).writer();
		for (i in 0...5000)
			w.push(i);
		eq(w.length, 5000, "a writer's length");
		eq(w.grow.length, 5000, "... is the Grow's");
		eq(w.grow[4999], 4999, "a writer's pushes, across growth");
		var ws = Scope.grow(Vec2).writer();
		ws.next().x = 3;
		eq(ws.grow[0].x, 3.0, "a writer's next()");
		var two = Scope.grow(Float);
		two.push(1.5);
		eq(Scope.grows() >= 3, true, "Grows claimed");
	}

	@:scoped static function strings() {
		var s = Str.of("héllo wörld");
		eq(s.length, 13, "UTF-8 length in bytes");
		eq(s.toString(), "héllo wörld", "round trip");
		eq(s.indexOf("wörld"), 7, "indexOf");
		eq(s.sub(7, 6).toString(), "wörld", "sub");
		eq(s == Str.of("héllo wörld"), true, "==");
		eq(s == "héllo", false, "!=");
		eq(Str.of("a").compare("b") < 0, true, "compare");
		eq((Str.of("ab") + "cd").toString(), "abcd", "+");
		eq(s.startsWith("hé"), true, "startsWith");
		eq(Str.of("x").hash() == Str.of("x").hash(), true, "hash");
		var b = new StrBuf();
		b.addString("n=");
		b.addInt(42);
		b.add(Str.of("!"));
		eq(b.toString(), "n=42!", "StrBuf");
		eq(b.toStr().length, 5, "StrBuf.toStr");
	}

	@:scoped static function values() {
		eq(V3.SIZE, 24, "V3.SIZE");
		eq(Tagged.SIZE, 32, "Tagged.SIZE (a value inside a value)");
		eq(Body.SIZE, 64, "Body.SIZE");
		var bs = Scope.slice(Body, 10);
		for (i in 0...bs.length) {
			var b = bs[i];
			b.pos = new V3(i, i * 2, i * 3).scale(2);
			b.tag = new Tagged(b.pos.add(new V3(1, 1, 1)), i, i % 2 == 1);
			b.mass = i;
		}
		eq(bs[4].pos.y, 16.0, "a value field, stored and loaded");
		eq(bs[4].tag.at.z, 25.0, "a value inside a value");
		eq(bs[5].tag.on, true, "a value's Bool");
		eq(bs[5].tag.id, 5, "a value's Int");
		var sum = new V3(0, 0, 0);
		for (b in bs)
			sum = sum.add(b.pos);
		eq(sum.x, 90.0, "values summed in a loop");
		var before = Scope.used();
		var v = bs[3].pos;
		bs[3].pos = new V3(0, 0, 0);
		eq(v.x, 6.0, "a loaded value is a copy");
		eq(Scope.used(), before, "values take no scoped memory");
	}

	@:scoped static function bytes() {
		// F32: 4 bytes, read as a Float rounded to f32
		var f = Scope.slice(F32, 3);
		f[1] = 0.5;
		f[2] = 0.1;
		eq(f[1], 0.5, "F32 exact");
		eq(Math.abs(f[2] - 0.1) < 1e-8 && f[2] != 0.1, true, "F32 rounded");
		var ps = Scope.grow(Particle);
		var q = ps.next();
		q.life = 7;
		q.pos.x = 2;
		ps.push(q);
		eq(ps.length, 2, "Grow of structs: next and push");
		eq(ps[1].life, 7, "push copies the struct");
		eq(ps[0].alive, false, "next zeroes");
		// U8 arithmetic and comparisons as Ints
		var u = Scope.slice(U8, 2);
		u[0] = 200;
		eq(u[0] * 2, 400, "U8 * Int");
		eq(u[0] > 100, true, "U8 > Int");
		eq('0'.code <= u[0], true, "Int <= U8");
		// a byte writer: literal, Str, Ints; multi-byte reads
		var w = Scope.grow(U8).writer();
		w.addString("héllo, ");
		w.addStr(Str.of("world"));
		w.pushI32(-2);
		w.pushI16(0x1234);
		var g = w.grow;
		eq(g.length, 8 + 5 + 4 + 2, "byte writer length");
		eq(Str.of("héllo, world").toString(), Span.ofSlice(g.slice()).sub(0, 13).toString(), "addString, addStr");
		eq(g.getI32At(13), -2, "pushI32, getI32At");
		eq(g.getU16At(17), 0x1234, "pushI16, getU16At");
		var bs = g.slice();
		bs.setI32At(1, 0x01020304);
		eq(bs.getI32At(1), 0x01020304, "unaligned I32");
		eq(bs.getI16At(17), 0x1234, "getI16At");
		checks++;
		try {
			bs.getI32At(bs.length - 3);
			fail("multi-byte read past the end");
		} catch (e:Memory.ScopedError) {}
		// Span: a run of bytes as a value
		var a = Span.of(Str.of("abcabc"));
		eq(a.sub(0, 3).equals(a.sub(3, 3)), true, "Span.equals");
		eq(a.sub(0, 3).hash() == Span.of(Str.of("abc")).hash(), true, "Span.hash");
		eq(a.get(4), 'b'.code, "Span.get");
		checks++;
		try {
			a.get(6);
			fail("Span index past the end");
		} catch (e:Memory.ScopedError) {}
	}

	@:scoped static function scopes() {
		var before = Scope.used(), grows = Scope.grows();
		big();
		eq(Scope.used(), before, "a @:scoped function frees");
		eq(Scope.grows(), grows, "a @:scoped function releases Grows");
		loop(1000);
		eq(Scope.used(), before, "a loop frees");
		eq(made(10).length, 10, "a function returning a scoped value keeps it");
		eq(Scope.used() > before, true, "... in the caller's scope");
		var after = Scope.used();
		eq(caught(), true, "an exception through a @:scoped function");
		eq(Scope.used(), after, "freed by the function that caught it");
		eq(caughtInLoop(), 3, "exceptions caught in a loop");
		eq(Scope.used(), after, "freed by the loop's iterations");
		eq(viewLoops(), 4950 + 99.0 + 3, "loops over a slice read through a view");
		eq(earlyReturn(true), 1, "early return");
		eq(Scope.used(), after, "an early return frees");
	}

	@:scoped static function big() {
		var big = Scope.slice(Float, 100000);
		big[0] = 1;
		Scope.grow(Int).push(1);
	}

	@:scoped static function thrower() {
		Scope.slice(Int, 1000);
		throw new Memory.ScopedError("thrown");
	}

	@:scoped static function caught():Bool {
		try {
			thrower();
			return false;
		} catch (e:Memory.ScopedError) {
			return true;
		}
	}

	@:scoped static function caughtInLoop():Int {
		var n = 0, used = Scope.used();
		for (i in 0...3) {
			try
				thrower()
			catch (e:Memory.ScopedError)
				n++;
		}
		eq(Scope.used(), used, "the iterations reclaim what the exceptions kept");
		return n;
	}

	#if (target.threaded && (target.name == "hxmc" || scoped_threads))
	// 40 threads, 4 at a time: each its own stack (31 buffers in all, so a
	// stack not given back runs out)
	static function threads() {
		var results = new sys.thread.Deque<Int>();
		var total = 0;
		for (round in 0...10) {
			for (k in 0...4)
				sys.thread.Thread.create(() -> results.add(threadWork(round * 4 + k)));
			for (k in 0...4)
				total += results.pop(true);
		}
		// (each thread sums 0...1000 times n + 1, for n 0...40)
		eq(total, 499500 * (40 * 41 >> 1), "40 threads, each its own stack");
	}

	@:scoped static function threadWork(n:Int):Int {
		var s = Scope.slice(Int, 1000);
		var g = Scope.grow(Int);
		for (i in 0...s.length) {
			s[i] = i * (n + 1);
			g.push(s[i]);
		}
		var sum = 0;
		for (v in g)
			sum += v;
		return sum;
	}
	#end

	// each iteration's memory freed when the next starts
	@:scoped static function loop(n:Int) {
		var peak = 0;
		for (i in 0...n) {
			var tmp = Scope.slice(Int, 1000);
			tmp[0] = i;
			if (Scope.used() > peak)
				peak = Scope.used();
		}
		eq(peak < Scope.used() + 8000, true, "a loop's iterations reuse their memory");
	}

	// (Scoped's loops over a slice: s[i] through a view; the last loop
	// reassigns s, so it keeps the checked access)
	@:scoped static function viewLoops():Float {
		var s = Scope.slice(Int, 100);
		for (i in 0...s.length)
			s[i] = i;
		var sum = 0;
		for (i in 0...s.length)
			sum += s[i];
		var ps = Scope.slice(Particle, 100);
		for (i in 0...ps.length)
			ps[i].pos.x = i;
		var last = 0.0;
		for (i in 0...ps.length)
			last = ps[i].pos.x;
		var t = Scope.slice(Int, 3), u = Scope.slice(Int, 3), n = 0;
		for (i in 0...t.length) {
			t[i] = 1;
			n += t[i];
			t = u;
		}
		return sum + last + n;
	}

	@:scoped static function made(n:Int):Slice<Int> {
		var s = Scope.slice(Int, n);
		s[0] = 1;
		return s;
	}

	@:scoped static function earlyReturn(b:Bool):Int {
		var s = Scope.slice(Int, 100);
		s[0] = 1;
		if (b)
			return s[0];
		return 2;
	}
}
