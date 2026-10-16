import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Flow.*;
import hxmc.ui.reactive.Reactive.*;

// hxmc.ui.reactive's tests, on Eval (make ui-check runs them after UiTest):
// signals, memos and effects (tracking, batching, no glitches, ownership
// and cleanup), then markup rendered into nodes (Render): elements and
// style attributes, text runs, reactive text and attributes, regions,
// For and Show, components, events through a Ui
class ReactiveTest implements Markup {
	static var checks = 0;
	static var failed = 0;

	public static function main() {
		signals();
		rendering();
		Sys.println('ReactiveTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('ReactiveTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function signals() {
		var a = signal(1), b = signal(2);
		var runs = 0, seen = 0;
		var e = effect(() -> {
			runs++;
			seen = a.value + b.value;
		});
		check("effect runs at once", runs == 1 && seen == 3);
		a.value = 10;
		check("effect reruns on a write", runs == 2 && seen == 12);
		a.value = 10;
		check("the same value notifies nothing", runs == 2);
		batch(() -> {
			a.value = 1;
			b.value = 1;
		});
		check("a batch runs effects once", runs == 3 && seen == 2);
		// memos: lazy, cached, no glitches (a diamond)
		var x = signal(1);
		var computeB = 0, computeC = 0;
		var bm = memo(() -> {
			computeB++;
			x.value * 2;
		});
		var cm = memo(() -> {
			computeC++;
			x.value + 1;
		});
		var log = [];
		effect(() -> log.push(bm.value + "/" + cm.value));
		x.value = 5;
		check("diamond: one consistent run per write", log.join(" ") == "2/2 10/6", log.join(" "));
		var y = signal(3);
		var parity = memo(() -> y.value % 2);
		var pruns = 0;
		effect(() -> {
			parity.value;
			pruns++;
		});
		y.value = 5;
		check("a memo whose result is the same stops propagation", pruns == 1);
		y.value = 6;
		check("and propagates when it differs", pruns == 2);
		// untrack
		var u = signal(1), ur = 0;
		effect(() -> {
			untrack(() -> u.value);
			ur++;
		});
		u.value = 2;
		check("untrack does not track", ur == 1);
		// ownership: inner effects disposed when the outer reruns; cleanups
		var outer = signal(0), inner = signal(0), innerRuns = 0, cleaned = 0;
		effect(() -> {
			outer.value;
			effect(() -> {
				inner.value;
				innerRuns++;
			});
			onCleanup(() -> cleaned++);
		});
		inner.value = 1;
		check("inner effect runs", innerRuns == 2);
		outer.value = 1;
		check("outer rerun disposes the inner one and cleans up", cleaned == 1 && innerRuns == 3);
		inner.value = 2;
		check("only the new inner effect runs", innerRuns == 4, '$innerRuns');
		// a root's dispose
		var r = signal(0), rruns = 0;
		var dispose = root(d -> {
			effect(() -> {
				r.value;
				rruns++;
			});
			d;
		});
		dispose();
		r.value = 1;
		check("a disposed root's effects stop", rruns == 1);
		e.dispose();
		a.value = 100;
		check("a disposed effect stops", runs == 3);
	}

	static function Counter(props:{start:Int, ?label:String}):Esx {
		var count = signal(props.start);
		return <view direction="row" column-gap={4}>
			<text>{props.label ?? "count"}: {count}</text>
			<view tag="inc" focusable onClick={_ -> count.value++} padding={2}>+</view>
		</view>;
	}

	static function rendering() {
		var ui = new Ui(new MonoText(), 300, 200);
		ui.root.style.fontSize = 10; // 5 per character, 12.5 a line
		var name = signal("Ann");
		var wide = signal(false);
		var items = signal(["a", "b", "c"]);
		var shown = signal(true);
		var made = 0;
		var dispose = Render.render(<view padding="4 8" background="#eeeeee">
			<view tag="row" direction="row" justify="space-between" width={() -> wide.value ? 200 : 100}>
				Hello {name}!
			</view>
			<Counter start={1}/>
			<view tag="list"><For each={items} render={(i:String) -> {
				made++;
				<text>{i}</text>;
			}}/></view>
			<Show when={shown} fallback="hidden">
				<text tag="shown">visible</text>
			</Show>
		</view>, ui.root);
		ui.update();
		var top = ui.root.children[0];
		check("render: a view with its style", top.style.background == Color.rgb(0xEEEEEE) && top.style.padding.left == 8);
		var row = top.find("row");
		check("render: style attributes", row.style.direction == Row && row.style.justify == SpaceBetween && row.width == 100, '$row');
		var hello:TextNode = cast row.children[0];
		check("render: a text run is one TextNode", row.children.length == 1 && hello.text == "Hello Ann!", [for (c in row.children) c.tag].join(","));
		name.value = "Bo";
		check("render: reactive text", hello.text == "Hello Bo!");
		wide.value = true;
		ui.update();
		check("render: a reactive attribute", row.width == 200);
		// the counter
		var counter = top.children[1];
		var label:TextNode = cast counter.children[0];
		check("render: a component", label.text == "count: 1", label.text);
		var inc = counter.find("inc");
		check("render: a flag attribute", inc.focusable);
		ui.update();
		ui.pointerDown(inc.absX + 2, inc.absY + 2, 1);
		ui.pointerUp(inc.absX + 2, inc.absY + 2, 1);
		check("render: an event updates its signal", label.text == "count: 2", label.text);
		// For
		var list = top.find("list");
		function texts()
			return [for (c in list.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text].join(",");
		check("for: items", texts() == "a,b,c" && made == 3, texts());
		var firstB = list.children.filter(c -> Std.isOfType(c, TextNode))[1];
		items.value = ["c", "b", "d"];
		check("for: reordered, one made", texts() == "c,b,d" && made == 4, texts() + " " + made);
		check("for: kept nodes", list.children.filter(c -> Std.isOfType(c, TextNode))[1] == firstB);
		// Show
		check("show: when true", top.find("shown") != null);
		shown.value = false;
		var fallback = [for (c in top.children) if (Std.isOfType(c, TextNode)) (cast c : TextNode).text];
		check("show: the fallback", top.find("shown") == null && fallback.contains("hidden"), fallback.join(","));
		shown.value = true;
		check("show: back", top.find("shown") != null);
		dispose();
		check("render: dispose removes the content", ui.root.children.length == 0);
		name.value = "gone";
		check("render: and stops its effects", hello.text == "Hello Bo!");
	}
}
