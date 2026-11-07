// title: A million rows
// summary: VirtualList over a million rows of their own heights: scrolled, jumped to the end, the keyboard, rows put in above without a move
// tags: ui, view, virtual list
// demo: canvas 480x640
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.ui.view.UiFlow.*;
import helder.view.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// A million messages in a VirtualList (helder.ui.VirtualScroll): only the
// rows in view are made, each as tall as its text wraps (a day's header,
// a message of one to four lines), estimated until shown and measured, the
// scroll anchored to the row at the top. The toolbar jumps to the top, the
// middle and the end and puts three rows in above the first in view (the
// view does not move); the keyboard moves the selection, onto rows not made
// yet. The items are numbers, each row's content made from its own (as an
// app's rows would come from a store). (examples/ts-million in TypeScript;
// tests/headless/million.json drives it headless.)
class Million implements Markup {
	public static inline var COUNT = 1000000;

	static function main() {
		UiWindow.run(<Surface title="A million rows" width={480} height={640}>{new Million().view()}</Surface>);
	}

	public final items:Signal<Array<Int>>;
	public final selected:Signal<Dynamic> = signal((null : Dynamic));
	var list:Null<VirtualScroll> = null;
	var added = COUNT;

	// (count rows: a million)
	public function new(count = COUNT)
		items = signal([for (i in 0...count) i]);

	// three rows put in before the first in view: it stays where it is
	public function insertAbove() {
		var at = list == null ? 0 : list.firstVisible();
		if (at < 0) at = 0;
		var next = items().copy();
		for (_ in 0...3)
			next.insert(at, added++);
		items(next);
	}

	static final NAMES = ["Ada", "Grace", "Linus", "Margaret", "Ken", "Barbara", "Dennis", "Frances", "Alan", "Radia", "Edsger", "Hedy"];
	static final COLORS = ["#ef4444", "#f97316", "#eab308", "#22c55e", "#14b8a6", "#3b82f6", "#6366f1", "#a855f7", "#ec4899", "#64748b"];
	static final SENTENCES = [
		"Only the rows in view are made.", "The others are a number each in a sum tree of heights.", "Scrolling a million rows costs what twenty do.",
		"Each row is measured the first time it is shown.", "Until then its height is the estimate.", "The scroll stays on the row at the top.",
		"Rows put in above it move nothing.", "End jumps to the last row, made and measured on the way.", "The arrow keys walk onto rows not made yet.",
		"A row that leaves the view is kept for a while.", "Coming back to it makes nothing new.", "Selection is a key, so it outlives its row's node."
	];

	static function hash(i:Int):Int {
		var h = i * 0x45d9f3b;
		h = (h ^ (h >>> 16)) * 0x45d9f3b;
		return (h ^ (h >>> 16)) & 0x7fffffff;
	}

	// (a day's header every 200 rows)
	public static function isDay(id:Int):Bool
		return id < COUNT && id % 200 == 0;

	public static function author(id:Int):String
		return id >= COUNT ? "New" : NAMES[hash(id) % NAMES.length];

	// a message of one to six sentences (one line to four)
	public static function message(id:Int):String {
		if (id >= COUNT) return "Put in above the first row in view.";
		var h = hash(id + 7), n = 1 + (h % 4 == 0 ? h % 6 : h % 2), out = [];
		for (k in 0...n)
			out.push(SENTENCES[(h + k * 5) % SENTENCES.length]);
		return out.join(" ");
	}

	public static function thousands(n:Int):String {
		var s = Std.string(n), out = "";
		while (s.length > 3) {
			out = "," + s.substr(s.length - 3) + out;
			s = s.substr(0, s.length - 3);
		}
		return s + out;
	}

	static function Button(props:{tag:String, label:String, onClick:Void->Void}):View
		return <view:button tag={props.tag} role="button" focusable cursor="pointer" padding="4 10" radius={6} background="#18181b" color="#fafafa"
			onPress={props.onClick}>{props.label}</view:button>;

	// a row: a day's header, or a message (its author's initial, name and number, its text)
	static function Row(props:{id:Read<Int>, selected:Signal<Dynamic>}):View {
		var id = untrack(() -> props.id());
		if (isDay(id))
			return <view tag="day" padding="6 16" background="#f4f4f5">
				<text font-size={11} font-weight={700} color="#71717a">{"Day " + thousands(Std.int(id / 200) + 1)}</text>
			</view>;
		var name = author(id);
		return <view tag="message" direction="row" column-gap={10} padding="8 16" background={props.selected() == id ? "#dbeafe" : "#ffffff"}>
			<view width={32} height={32} radius={16} shrink={0} background={id >= COUNT ? "#18181b" : COLORS[hash(id + 3) % COLORS.length]} align-items="center"
				justify="center"><text color="#ffffff" font-weight={700}>{name.charAt(0)}</text></view>
			<view grow={1} shrink={1} min-width={0} row-gap={2}>
				<view direction="row" column-gap={6}><text font-weight={700}>{name}</text><text color="#a1a1aa">{"#" + thousands(id)}</text></view>
				<text color="#3f3f46">{message(id)}</text>
			</view>
		</view>;
	}

	public function view():View {
		return <view grow={1} background="#fafafa" font-family="DejaVu Sans" font-size={13} color="#18181b">
			<view tag="toolbar" direction="row" align-items="center" column-gap={6} padding="8 12" background="#ffffff">
				<text tag="title" grow={1} font-weight={700}>A million rows</text>
				<Button tag="top" label="Top" onClick={() -> list.focusIndex(0)}/>
				<Button tag="middle" label="Middle" onClick={() -> list.scrollToIndex(Std.int(items().length / 2), "start")}/>
				<Button tag="end" label="End" onClick={() -> list.focusIndex(items().length - 1)}/>
				<Button tag="insert" label="Insert" onClick={insertAbove}/>
			</view>
			<VirtualList tag="rows" each={items} estimate={52} selected={selected} label="Messages" ref={l -> list = l}>{(id:Read<Int>, i:Int) ->
				<Row id={id} selected={selected}/>}</VirtualList>
			<view tag="status" direction="row" padding="6 12" background="#ffffff">
				<text tag="status-text" color="#71717a">{thousands(items().length) + " rows" + (selected() == null ? "" : " · #" + thousands(selected()) + " selected")}</text>
			</view>
		</view>;
	}
}
