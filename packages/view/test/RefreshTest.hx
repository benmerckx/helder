import hxmc.view.*;
import hxmc.view.Flow.*;
import hxmc.view.Reactive.*;
import TestRenderer.TestNode;

// hxmc.view's fast refresh (-D hxmc.dev, hxmc.view.Refresh) across a
// reload, as HotTest does for hxmc.dev.Hot: the program runs twice (make
// dev-check), once changing its state and writing the snapshot, then
// started from it (HXMC_DEV_SNAPSHOT):
//   <tool> -cp packages/os/src -cp packages/view/src -cp packages/view/test \
//     -D hxmc.view.renderer=TestRenderer -D hxmc.dev --run RefreshTest save|restore <file>
// signals keyed by their variables, in each component instance's scope:
// two instances of one component apart, a list's rows by position, a
// component by its key attribute, what a region shows later (Show) as when it
// first showed; a signal of a type that is not data not kept; the effects'
// cleanups run on disposal
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
		var names:Signal<Array<String>> = signal([]);
		var later = signal(false);
		var callback = signal(() -> 1);
		var root = TestRenderer.createElement("div");
		Render.render(<div>
			<Card label="a"/>
			<Card label="b"/>
			<For each={names} render={(n:String) -> <Card label={"row " + n}/>}/>
			<Card key="k" label="keyed"/>
			<Show when={later}><Card label="later"/></Show>
		</div>, root);
		switch phase {
			case "save":
				check("a cold start", !hxmc.dev.Hot.reloading && count.value == 0 && made.get("a").value == 0);
				count.value = 5;
				made.get("a").value = 1;
				made.get("b").value = 2;
				made.get("keyed").value = 4;
				names.value = ["x", "y"];
				made.get("row x").value = 10;
				made.get("row y").value = 11;
				later.value = true;
				made.get("later").value = 7;
				callback.value = () -> 2;
				sys.io.File.saveContent(file, hxmc.dev.Hot.snapshot());
				hxmc.dev.Hot.dispose();
				check("disposed: the effects' cleanups ran", cleaned >= 6);
			case _:
				check("reloading", hxmc.dev.Hot.reloading);
				check("a signal by its variable", count.value == 5);
				check("an array by the type expected", names.value.join(",") == "x,y");
				check("instances apart", made.get("a").value == 1 && made.get("b").value == 2);
				check("by the key attribute", made.get("keyed").value == 4);
				check("rows by position", made.get("row x").value == 10 && made.get("row y").value == 11);
				check("a region shown later", later.value && made.get("later") != null && made.get("later").value == 7);
				check("not data: not kept", callback.value() == 1);
				hxmc.dev.Hot.framed();
		}
		Sys.println(failures == 0 ? 'RefreshTest $phase: ok' : 'RefreshTest $phase: $failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
