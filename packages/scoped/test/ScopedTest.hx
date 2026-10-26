import hxmc.scoped.*;

@:build(hxmc.scoped.Struct.build())
abstract Vec2(Addr) {
	var x:Float;
	var y:Float;
}

@:build(hxmc.scoped.Struct.build())
abstract Particle(Addr) {
	var pos:Vec2;
	var life:Int;
	var alive:Bool;
	var tag:U8;
}

// hxmc.scoped on any target: `haxe -cp packages/scoped/src -cp packages/scoped/test
// -main ScopedTest --macro hxmc.scoped.Check.enable() <target>`; prints "ok" and
// the number of checks, exits 1 on a failure.
@:build(hxmc.scoped.Scoped.build())
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
		scopes();
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
	}

	@:scoped static function scalars() {
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
