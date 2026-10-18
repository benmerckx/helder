import hxmc.dev.Hot;
import store.Store;

// hxmc.dev.Hot's primitives across a reload, without the dev server: the
// program runs twice (make dev-check), as two builds would under `hxmc dev`:
//   HotTest save <file>      changes its state, writes the snapshot (what
//                            the dev server asks a build for) to file
//   HotTest restore <file>   started with HXMC_DEV_SNAPSHOT=<file>: the state
//                            is back, by key (built with -D hot_changed: the
//                            value whose type changed is reset, logged)
// The store (test/store/Store.hx) is a third-party library: Hot's public
// calls only.
typedef Cart = {items:Array<String>, total:Float};

enum Mode {
	Idle;
	Busy(n:Int);
}

class Point {
	public var x:Int;
	public var y:Int;

	public function new(x:Int, y:Int) {
		this.x = x;
		this.y = y;
	}
}

class Tree {
	public var label:String;
	public var children:Array<Tree> = [];

	public function new(label:String)
		this.label = label;
}

class HotTest {
	static var failures = 0;

	static function check(what:String, ok:Bool) {
		if (!ok) {
			failures++;
			Sys.println("FAIL " + what);
		}
	}

	// a component's state: the same static key in each instance, the instance's scope apart
	static function card(name:String):{value:Int}
		return Hot.scope(name, () -> Hot.keep("state", () -> {value: 0}));

	static function main() {
		var args = Sys.args();
		var phase = args[0], file = args[1];

		// a store, keyed by its variable (HotTest.main.cart)
		var cart = Store.create(({items: [], total: 0.0} : Cart));
		// app-level values with keys of their own
		var point = Hot.keep("point", () -> new Point(0, 0));
		var tree = Hot.keep("tree", () -> new Tree("root"));
		// two instances of one component (Card, Card#1) and one in a scope of its own
		var a = card("Card"), b = card("Card"), c = Hot.scope("List", () -> card("Card"));
		// a value whose type changes between the builds: reset, never cast
		#if hot_changed
		var changed:Null<String> = Hot.load("changed", Hot.typeOf((_ : String)));
		#else
		var changed:Null<Int> = Hot.load("changed", Hot.typeOf((_ : Int)));
		#end
		var mode:Null<Mode> = Hot.load("mode", Hot.typeOf((_ : Mode)));
		var where = Hot.here();
		var disposed = [];
		Hot.onDispose(() -> disposed.push("first"));
		Hot.onDispose(() -> disposed.push("second"));
		// a Void function in a scope
		var ran = false;
		Hot.scope("void", () -> {
			ran = true;
		});

		check("here " + where, where == "HotTest.main.where");
		check("scope runs", ran);
		check("data types hashed", Hot.typeOf((_ : Int)) != "" && Hot.typeOf((_ : Cart)) != "" && Hot.typeOf((_ : Tree)) != ""
			&& Hot.typeOf((_ : Mode)) != "" && Hot.typeOf((_ : Map<String, Array<Float>>)) != "");
		check("shapes differ", Hot.typeOf((_ : {a:Int})) != Hot.typeOf((_ : {a:Float})) && Hot.typeOf((_ : Int)) != Hot.typeOf((_ : String)));
		check("one shape one hash", Hot.typeOf((_ : {a:Int, b:String})) == Hot.typeOf((_ : {b:String, a:Int})) && Hot.typeOf(point) == Hot.typeOf((_ : Point)));
		check("not data", Hot.typeOf((_ : Int->Int)) == "" && Hot.typeOf((_ : Dynamic)) == "" && Hot.typeOf((_ : {f:Void->Void})) == ""
			&& Hot.typeOf((_ : Array<Dynamic>)) == "");

		switch phase {
			case "save":
				check("cold start", !Hot.reloading);
				check("fresh store", cart.state.items.length == 0);
				cart.update(s -> {items: s.items.concat(["pen"]), total: s.total + 1.5});
				point.x = 4;
				tree.children.push(new Tree("leaf"));
				a.value = 1;
				b.value = 2;
				c.value = 3;
				Hot.save("changed", 42, Hot.typeOf((_ : Int)));
				Hot.save("mode", Busy(7), Hot.typeOf((_ : Mode)));
				Hot.save("gone", "nothing asks for it", Hot.typeOf((_ : String)));
				sys.io.File.saveContent(file, Hot.snapshot());
				Hot.dispose();
				check("disposed, last given first: " + disposed, disposed.join(",") == "second,first");
			case _:
				check("reloading", Hot.reloading);
				check("store kept: " + cart.state, cart.state.items.join(",") == "pen" && cart.state.total == 1.5);
				check("object kept", point.x == 4 && point.y == 0);
				check("graph kept", tree.children.length == 1 && tree.children[0].label == "leaf");
				check("instances apart: " + [a.value, b.value, c.value], a.value == 1 && b.value == 2 && c.value == 3);
				check("enum kept", mode != null && Type.enumEq(mode, Busy(7)));
				#if hot_changed
				check("type changed: reset", changed == null);
				#else
				check("value kept", changed == 42);
				#end
				check("loaded once", Hot.load("mode", Hot.typeOf((_ : Mode))) == null);
				Hot.framed();
				check("started", !Hot.reloading);
		}
		Sys.println(failures == 0 ? 'HotTest $phase: ok' : 'HotTest $phase: $failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
