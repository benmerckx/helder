package helder.ui.actions;

import helder.ui.actions.ContextPredicate;

// Key bindings: keystroke sequences to actions where a context predicate
// holds (GPUI's keymap). An app adds its defaults (bind), a user's file
// overrides them (loadUser: JSON, read again when it changes, poll):
//
//   [{"context": "Viewer && !picker", "bindings": {"secondary-k secondary-z": "viewer::ZoomIn",
//     "1": ["viewer::ZoomTo", 100], "f11": null}}]
//
// (null: unbound there, the key passed on as if no binding had it). Of the
// bindings a key sequence matches, the one whose context holds deepest in
// the focus's context stack wins, then the later (the user's after the
// defaults, a file's later entries after its earlier); one whose action no
// handler on the dispatch path takes is passed over for the next. A
// sequence that begins a longer binding waits for its next keystroke
// (Ui's pending chord) for timeout seconds, then runs what its keys alone
// are bound to, if anything.
class Keymap {
	// secondary is Command (macOS), else Control; UiWindow sets it
	public static var mac = false;
	// how long a chord waits for its next keystroke (seconds)
	public static var timeout = 1.0;
	// the app's keymap, every window's unless given its own (Ui.keymap)
	public static final global = new Keymap();

	final defaults:Array<Binding> = [];
	var user:Array<Binding> = [];
	// the user's file, its last state (modification time and size), the last error
	var userPath:Null<String> = null;
	var userStamp = "";

	public var error(default, null):Null<String> = null;

	// bumped by each change (a menu's labels asked again)
	public var version(default, null) = 0;

	public function new() {}

	// a default binding (keys: "secondary-o", "secondary-k secondary-s"; context: a predicate, null: anywhere)
	public function bind(keys:String, action:Null<EnumValue>, ?context:String):Keymap {
		defaults.push(new Binding(Keystroke.sequence(keys), action, context));
		version++;
		return this;
	}

	// the bindings of a JSON keymap (Actions.parse's names)
	public static function parseJson(text:String):Array<Binding> {
		var out = [];
		var data:Dynamic = haxe.Json.parse(text);
		if (!Std.isOfType(data, Array)) data = [data];
		for (section in (data : Array<Dynamic>)) {
			var context:Null<String> = Reflect.field(section, "context");
			var bindings:Dynamic = Reflect.field(section, "bindings");
			if (bindings == null) continue;
			for (keys in Reflect.fields(bindings)) {
				var v:Dynamic = Reflect.field(bindings, keys);
				out.push(new Binding(Keystroke.sequence(keys), v == null ? null : Actions.parse(v), context));
			}
		}
		return out;
	}

	// a JSON keymap as the user's (after the defaults: theirs win)
	public function setUser(text:String) {
		user = parseJson(text);
		version++;
	}

	// the user's keymap file (a missing one: none); poll reads it again when it changed
	public function loadUser(path:String) {
		userPath = path;
		userStamp = "";
		poll();
	}

	// the user's file read again if it changed since (UiWindow: each second);
	// a bad one keeps the last good bindings, error says why
	public function poll():Bool {
		#if sys
		if (userPath == null) return false;
		var stamp = try {
			var s = sys.FileSystem.stat(userPath);
			s.mtime.getTime() + ":" + s.size;
		} catch (_:Dynamic) "none";
		if (stamp == userStamp) return false;
		userStamp = stamp;
		try {
			if (stamp == "none") user = [] else user = parseJson(sys.io.File.getContent(userPath));
			error = null;
		} catch (e:Dynamic) {
			error = userPath + ": " + Std.string(e);
		}
		version++;
		return true;
		#else
		return false;
		#end
	}

	// every binding, lowest precedence first
	public function bindings():Array<Binding>
		return defaults.concat(user);

	// the bindings a typed sequence matches in the stack: exactly (best
	// first), and whether any longer one begins with it there
	public function match(typed:Array<{key:Int, mods:Int}>, stack:Array<KeyContext>):{exact:Array<Binding>, longer:Bool, longerDepth:Int} {
		var all = bindings(), exact:Array<{b:Binding, depth:Int, at:Int}> = [], longer = false, longerDepth = -1;
		for (i in 0...all.length) {
			var b = all[i];
			if (b.keys.length < typed.length) continue;
			var ok = true;
			for (k in 0...typed.length)
				if (!b.keys[k].matches(typed[k].key, typed[k].mods)) {
					ok = false;
					break;
				}
			if (!ok) continue;
			var d = b.depth(stack);
			if (d < 0) continue;
			if (b.keys.length == typed.length) exact.push({b: b, depth: d, at: i}) else if (b.action != null) {
				longer = true;
				if (d > longerDepth) longerDepth = d;
			}
		}
		exact.sort((x, y) -> x.depth != y.depth ? y.depth - x.depth : y.at - x.at);
		return {exact: [for (e in exact) e.b], longer: longer, longerDepth: longerDepth};
	}

	// the key sequences bound to an action (best first) where the stack is
	// (null: anywhere), each one that would run it: not taken by a better
	// binding of the same keys first
	public function keysFor(action:EnumValue, ?stack:Array<KeyContext>):Array<Array<Keystroke>> {
		var all = bindings(), out:Array<{keys:Array<Keystroke>, depth:Int, at:Int}> = [];
		for (i in 0...all.length) {
			var b = all[i];
			if (b.action == null || !Actions.equals(b.action, action)) continue;
			var d = stack == null ? 0 : b.depth(stack);
			if (d < 0) continue;
			// (a better binding of the same keys: this one never runs)
			var best = i, bestDepth = d;
			for (j in 0...all.length) {
				var o = all[j];
				if (j == i || !sameKeys(o.keys, b.keys)) continue;
				var od = stack == null ? (o.predicate == null && b.predicate == null ? 0 : -1) : o.depth(stack);
				if (od > bestDepth || od == bestDepth && j > best) {
					best = j;
					bestDepth = od;
				}
			}
			var w = all[best];
			if (best == i || w.action != null && Actions.equals(w.action, action)) out.push({keys: b.keys, depth: d, at: i});
		}
		out.sort((x, y) -> x.depth != y.depth ? y.depth - x.depth : y.at - x.at);
		return [for (o in out) o.keys];
	}

	// as a menu or a tooltip shows the best of them: "Ctrl+O", "⌘K ⌘S"; null: none
	public function label(action:EnumValue, ?stack:Array<KeyContext>):Null<String> {
		var k = keysFor(action, stack);
		return k.length == 0 ? null : [for (s in k[0]) s.label()].join(" ");
	}

	static function sameKeys(a:Array<Keystroke>, b:Array<Keystroke>):Bool {
		if (a.length != b.length) return false;
		for (i in 0...a.length)
			if (!a[i].equals(b[i])) return false;
		return true;
	}
}

class Binding {
	public final keys:Array<Keystroke>;
	// null: unbound (the keys passed on)
	public final action:Null<EnumValue>;
	public final context:Null<String>;
	public final predicate:Null<ContextPredicate>;

	public function new(keys:Array<Keystroke>, action:Null<EnumValue>, ?context:String) {
		if (keys.length == 0) throw "helder.ui: a binding without keys";
		this.keys = keys;
		this.action = action;
		this.context = context == null || StringTools.trim(context) == "" ? null : context;
		this.predicate = this.context == null ? null : Predicates.parse(this.context);
	}

	// how deep its predicate holds in the stack (no predicate: 0, everywhere; -1: not here)
	public function depth(stack:Array<KeyContext>):Int {
		if (predicate == null) return 0;
		var d = Predicates.depth(predicate, stack);
		return d == 0 ? -1 : d;
	}

	public function toString():String
		return [for (k in keys) k.toString()].join(" ") + " -> " + (action == null ? "null" : Actions.name(action))
			+ (context == null ? "" : " in " + context);
}
