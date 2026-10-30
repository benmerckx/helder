import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import TestRenderer.TestNode;

// helder.view's fast refresh (-D hxmc.dev, helder.view.Refresh) across a
// reload, as HotTest does for helder.dev.Hot: the program runs twice (make
// dev-check), once changing its state and writing the snapshot, then
// started from it (HXMC_DEV_SNAPSHOT):
//   <tool> -cp src -cp tests/view -D hxmc.dev --run RefreshTest save|restore <file>
// signals keyed by their variables, in each component instance's scope:
// two instances of one component apart, a list's rows by position, a
// component by its key attribute, what a region shows later (Show) as when it
// first showed; a signal of a value that is not data not kept (a generic
// class's instance among them); the effects' cleanups run on disposal. Built again with -D refresh_changed (a signal's
// initial value edited), restored from the same snapshot: that signal
// starts at its new value, said so, the others are kept; a class marked
// @:hot(reset) keeps none of its signals
class RefreshTest implements Markup {
	static var failures = 0;
	// the components' signals, by their labels
	static final made = new Map<String, Signal<Int>>();
	static var cleaned = 0;

	static function check(what:String, ok:Bool) {
		if (!ok) {
			failures++;
			Sys.println("FAIL " + what);
		}
	}

	static function Card(props:{label:String}):View {
		var clicks = signal(0);
		made.set(props.label, clicks);
		onCleanup(() -> cleaned++);
		return <p>{props.label}: {clicks}</p>;
	}

	static function main() {
		var args = Sys.args();
		var phase = args[0], file = args[1];
		var count = signal(0);
		var tuned = signal(#if refresh_changed 7 #else 1 #end);
		var fresh = ResetState.make();
		var names:Signal<Array<String>> = signal([]);
		var later = signal(false);
		var callback = signal({f: () -> 1});
		// (a class holding a generic one typed later: its type parameters'
		// constraints left alone, the program compiles under -D hxmc.dev)
		var game = signal(new refresh.Game());
		var root = TestRenderer.createElement("div");
		Render.render(<div>
			<Card label="a"/>
			<Card label="b"/>
			<For each={names}>{n -> <Card label={"row " + n()}/>}</For>
			<Card key="k" label="keyed"/>
			<Show when={later}><Card label="later"/></Show>
		</div>, root);
		switch phase {
			case "save":
				check("a cold start", !helder.dev.Hot.reloading && count() == 0 && made.get("a")() == 0);
				count(5);
				tuned(2);
				fresh(9);
				made.get("a")(1);
				made.get("b")(2);
				made.get("keyed")(4);
				names(["x", "y"]);
				flush();
				made.get("row x")(10);
				made.get("row y")(11);
				later(true);
				flush();
				made.get("later")(7);
				callback({f: () -> 2});
				flush();
				sys.io.File.saveContent(file, helder.dev.Hot.snapshot());
				helder.dev.Hot.dispose();
				check("disposed: the effects' cleanups ran", cleaned >= 6);
			case _:
				check("reloading", helder.dev.Hot.reloading);
				check("a signal by its variable", count() == 5);
				check("an array by the type expected", names().join(",") == "x,y");
				check("instances apart", made.get("a")() == 1 && made.get("b")() == 2);
				check("by the key attribute", made.get("keyed")() == 4);
				check("rows by position", made.get("row x")() == 10 && made.get("row y")() == 11);
				check("a region shown later", later() && made.get("later") != null && made.get("later")() == 7);
				check("not data: not kept", callback().f() == 1);
				#if refresh_changed
				check("its initial value edited: the new one", tuned() == 7);
				#else
				check("its initial value as it was: kept", tuned() == 2);
				#end
				check("@:hot(reset): not kept", fresh() == 0);
				helder.dev.Hot.framed();
		}
		Sys.println(failures == 0 ? 'RefreshTest $phase: ok' : 'RefreshTest $phase: $failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}

// (its signals start afresh in each build)
@:hot(reset)
class ResetState {
	public static function make():Signal<Int>
		return signal(0);
}
