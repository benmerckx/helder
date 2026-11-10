package helder.dev;

// Live literals (dev builds only, -D hxmc.dev): the literals of markup —
// attributes' values (numbers, strings, colours, lengths, flags), style
// props, text, the values of a ternary's branches in an attribute, a
// Color.rgb's channel — read from a slot table, so that `helder dev` (or the
// studio) patches them in the running program without a build. The markup
// planner (helder.markup.Plan, Haxe's markup and TSX alike) writes each
// such literal as a read of its slot:
//
//   Literals.string(id, "#3b82f6", anchor)     Literals.int(id, 24, anchor)
//   Literals.float(id, 1.5, anchor)            Literals.bool(id, true, anchor)
//
// A slot is a signal (helder.view.graph): a literal in a reactive position
// (an attribute, a text, a prop that reads) is bound as any read is, so a
// patch re-runs only what reads it; a read outside a computation (a
// component's prop of no Read type, read once) cannot follow a patch: the
// slot is stale, and a patch of it says so (helder dev builds then).
//
// An id is `<file>:<line>:<column>:<kind>` (the literal's place in the
// source it was built from, byte columns from 1; kind: color, length,
// number, string, text, boolean), stable across builds while the source
// before it does not move. A patch kept across a reload (Hot's snapshot)
// finds its slot again by id, else by its file, kind and anchor (its line's
// source, the literals' values left out) when one slot alone has them; it
// is kept only while the literal's compiled value is the one it replaced
// (a source changed there wins).
//
// Over the devtools protocol (helder.devtools.Agent), the method
// `Hot.literals`: `{}` lists the slots, `{set: [{id, value} | {id, source}]}`
// patches them (value: JSON of the slot's type; source: the literal as
// written, quotes and all, or a text's raw run) and answers `{set, stale,
// unknown}` (unknown: not read yet, kept for when it is); the first frame
// after a patch notifies `Hot.patched {ms, ids}`. helder.headless's script
// patches them too ({"literal": ...}).
#if (hxmc.dev && !macro)
class Literals {
	static final slots = new Map<String, Slot>();
	static final order:Array<Slot> = [];
	// patches of slots not read yet (by id)
	static final pending = new Map<String, Dynamic>();
	// the patches the last build kept (Hot's snapshot), until their slot is read
	static var restored:Null<Array<Kept>> = null;
	static var started = false;
	// a patch set, its frame to come
	static var patchedAt = -1.0;
	static var patchedIds:Array<String> = [];

	public static function string(id:String, value:String, anchor:String):String
		return read(id, value, anchor);

	public static function int(id:String, value:Int, anchor:String):Int
		return read(id, value, anchor);

	public static function float(id:String, value:Float, anchor:String):Float
		return read(id, value, anchor);

	public static function bool(id:String, value:Bool, anchor:String):Bool
		return read(id, value, anchor);

	static function read(id:String, value:Dynamic, anchor:String):Dynamic {
		var s = slots.get(id);
		if (s == null) s = add(id, value, anchor);
		if (@:privateAccess helder.view.graph.Node.observer == null) s.untracked = true;
		return s.node.read();
	}

	static function add(id:String, value:Dynamic, anchor:String):Slot {
		start();
		var s = new Slot(id, value, anchor);
		slots.set(id, s);
		order.push(s);
		var p = pending.get(id);
		if (p != null) {
			pending.remove(id);
			s.patch(p);
		} else restore(s);
		return s;
	}

	// (the first slot: the method, the snapshot's hook, the last build's patches)
	static function start() {
		if (started) return;
		started = true;
		helder.devtools.Agent.method("Hot.literals", call);
		Hot.at("", () -> {
			var kept:Null<Array<String>> = Hot.load("helder.literals", "helder.literals.1");
			if (kept != null) {
				var r:Array<Kept> = [];
				restored = r;
				var i = 0;
				while (i + 4 < kept.length) {
					r.push({id: kept[i], anchor: kept[i + 1], base: haxe.Unserializer.run(kept[i + 2]), value: haxe.Unserializer.run(kept[i + 3]),
						kind: kept[i + 4]});
					i += 5;
				}
			}
			Hot.onSnapshot(() -> {
				var a:Array<String> = [];
				for (s in order) if (s.patched) a = a.concat([s.id, s.anchor, haxe.Serializer.run(s.base), haxe.Serializer.run(s.node.peek()), s.kind]);
				// (those not read in this build, kept as they came)
				if (restored != null) for (k in restored) a = a.concat([k.id, k.anchor, haxe.Serializer.run(k.base), haxe.Serializer.run(k.value), k.kind]);
				Hot.save("helder.literals", a, "helder.literals.1");
			});
			null;
		});
		Hot.afterFrame = framed;
	}

	// a patch the last build kept: by id, else by file, kind and anchor (one alone), while its base is the literal's value
	static function restore(s:Slot) {
		var r = restored;
		if (r == null || r.length == 0) return;
		var match = Lambda.find(r, k -> k.id == s.id);
		if (match == null) {
			var file = Slot.fileOf(s.id);
			var same = r.filter(k -> k.kind == s.kind && k.anchor == s.anchor && Slot.fileOf(k.id) == file && slots.get(k.id) == null);
			if (same.length == 1) match = same[0];
		}
		if (match == null) return;
		r.remove(match);
		if (match.base == s.base) s.patch({value: match.value});
	}

	// Hot.literals: the slots, or patches
	static function call(params:Dynamic):Dynamic {
		var set:Null<Array<Dynamic>> = params == null ? null : params.set;
		if (set == null) return {literals: [for (s in order) s.describe()]};
		var done = [], stale = [], unknown = [];
		for (p in set) {
			var id:String = p.id;
			var s = slots.get(id);
			if (s == null) {
				pending.set(id, p);
				unknown.push(id);
				continue;
			}
			s.patch(p);
			done.push(id);
			if (s.untracked) stale.push(id);
		}
		helder.view.graph.Graph.flush();
		if (done.length > 0) {
			if (patchedAt < 0) patchedAt = haxe.Timer.stamp();
			patchedIds = patchedIds.concat(done);
		}
		return {set: done, stale: stale, unknown: unknown};
	}

	// a patch from this program (helder.headless's script): as Hot.literals' set
	public static function patch(set:Array<Dynamic>):Dynamic
		return call({set: set});

	// the slots (helder.headless's script: by file and value)
	public static function list():Array<Dynamic>
		return [for (s in order) s.describe()];

	// (Hot.framed) the first frame after a patch
	static function framed() {
		if (patchedAt < 0) return;
		var ms = Math.round((haxe.Timer.stamp() - patchedAt) * 10000) / 10;
		helder.devtools.Agent.notify("Hot.patched", {ms: ms, ids: patchedIds});
		patchedAt = -1;
		patchedIds = [];
	}
}

private typedef Kept = {id:String, anchor:String, base:Dynamic, value:Dynamic, kind:String};

private class Slot {
	public final id:String;
	public final anchor:String;
	public final kind:String;
	// the value compiled in
	public final base:Dynamic;
	public final node:helder.view.graph.Node<Dynamic>;
	// read outside a computation (a patch does not reach it)
	public var untracked = false;
	public var patched = false;

	public function new(id:String, value:Dynamic, anchor:String) {
		this.id = id;
		this.anchor = anchor;
		this.base = value;
		kind = id.substr(id.lastIndexOf(":") + 1);
		node = @:privateAccess helder.view.graph.Node.signal(value, null);
	}

	// a patch: {value} of the slot's type, or {source} as written
	public function patch(p:Dynamic) {
		var v:Dynamic = p.source != null ? parse(p.source) : p.value;
		if (Std.isOfType(base, Int) && !Std.isOfType(v, Int)) v = Std.int(v);
		else if (Std.isOfType(base, Float) && Std.isOfType(v, String)) v = Std.parseFloat(v);
		else if (Std.isOfType(base, Bool)) v = v == true || v == "true";
		else if (Std.isOfType(base, String) && !Std.isOfType(v, String)) v = Std.string(v);
		patched = v != base;
		node.set(v);
	}

	// a literal's source: a quoted string, a number, true or false, else a text's raw run
	function parse(source:String):Dynamic {
		var t = StringTools.trim(source);
		if (t.length >= 2 && (t.charAt(0) == '"' || t.charAt(0) == "'" || t.charAt(0) == "`")) return unquote(t);
		if (t == "true" || t == "false") return t == "true";
		if (kind == "number" || (kind == "color" && !Std.isOfType(base, String))) {
			var n = Std.parseFloat(t);
			if (StringTools.startsWith(t, "0x") || StringTools.startsWith(t, "0X")) return Std.parseInt(t);
			return Std.isOfType(base, Int) ? Std.int(n) : n;
		}
		// (a text: JSX's whitespace rule, its entities)
		var c = helder.markup.Syntax.Whitespace.clean(source);
		return c == null ? "" : helder.markup.Syntax.Entities.decode(c);
	}

	static function unquote(t:String):String {
		var b = new StringBuf(), i = 1, end = t.length - 1;
		while (i < end) {
			var c = t.charAt(i);
			if (c == "\\" && i + 1 < end) {
				var n = t.charAt(i + 1);
				i += 2;
				switch n {
					case "n": b.add("\n");
					case "t": b.add("\t");
					case "r": b.add("\r");
					case "0": b.add("\x00");
					case "u" if (t.charAt(i) == "{"):
						var close = t.indexOf("}", i);
						b.addChar(Std.parseInt("0x" + t.substring(i + 1, close)) ?? 0xFFFD);
						i = close + 1;
					case "u":
						b.addChar(Std.parseInt("0x" + t.substr(i, 4)) ?? 0xFFFD);
						i += 4;
					case "x":
						b.addChar(Std.parseInt("0x" + t.substr(i, 2)) ?? 0xFFFD);
						i += 2;
					case _: b.add(n);
				}
				continue;
			}
			b.add(c);
			i++;
		}
		return b.toString();
	}

	public static function fileOf(id:String):String {
		var parts = id.split(":");
		return parts.slice(0, parts.length - 3).join(":");
	}

	public function describe():Dynamic {
		var parts = id.split(":");
		var n = parts.length;
		return {
			id: id,
			file: parts.slice(0, n - 3).join(":"),
			line: Std.parseInt(parts[n - 3]),
			column: Std.parseInt(parts[n - 2]),
			kind: kind,
			value: node.peek(),
			base: base,
			patched: patched,
			live: !untracked
		};
	}
}
#end
