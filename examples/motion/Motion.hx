// title: Motion
// summary: Motion as property tracks: a list adding and removing rows, a tile grid zooming into a matched tile, a theme switch, reduced motion
// tags: ui, view, motion
// demo: canvas 760x520
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// Motion declared on nodes, not coded per widget (helder.ui.motion): the
// list's motion="default" moves each row edge by edge as rows come and go
// (a row's transition="fade slide-up" plays as it enters and as it leaves,
// drawn until its exit settles; one put back mid-exit is revived from
// where it is); the grid's tiles are matched="tile-<n>": zoomed, the one
// picked flies from its place in the grid to the whole stage, its radius
// with it, and back; the theme's colours move through OKLab (the text's in
// half the time, keeping its contrast); reduced motion snaps travel and
// keeps a short fade. A tile pressed zooms into it, pressed again back.
// examples/motion/main.tsx is the same in TypeScript; tests/headless's
// motion.json scripts it (helder run --headless --trace: its continuity
// checked, its frames strips).
class Motion implements Markup {
	static function main() {
		UiWindow.run(<Surface title="Motion" width={760} height={520}>{view()}</Surface>);
	}

	static final rows = signal([1, 2, 3, 4]);
	static var next = 5;
	static final dark = signal(false);
	static final reduced = signal(false);
	// the tile zoomed into (-1: the grid)
	static final zoomed = signal(-1);

	static final TILES = ["#f97316", "#22c55e", "#3b82f6", "#a855f7"];

	public static function add()
		rows(rows().concat([next++]));

	public static function removeOne() {
		var r = rows();
		if (r.length > 0) rows(r.filter(x -> x != r[r.length > 2 ? 1 : 0]));
	}

	public static function shuffle() {
		var r = rows().copy();
		r.reverse();
		rows(r.length > 2 ? r.slice(1).concat([r[0]]) : r);
	}

	public static function setReduced(on:Bool) {
		reduced(on);
		Clock.reducedMotion = on;
	}

	static function Button(props:{tag:String, label:Read<String>, onPress:Void->Void}):View
		return <view:button tag={props.tag} role="button" focusable cursor="pointer" padding="6 12" radius={8}
			background={dark() ? "#27272a" : "#ffffff"} color={dark() ? "#fafafa" : "#18181b"} border-width={1} border-color={dark() ? "#3f3f46" : "#e4e4e7"}
			onPress={props.onPress}>{props.label()}</view:button>;

	static function tile(i:Int, big:Bool):View
		return <view tag={"tile-" + i} matched={"tile-" + i} grow={1} radius={big ? 28 : 16} background={TILES[i]} padding={16} cursor="pointer"
			justify="end" onClick={() -> zoomed(big ? -1 : i)}>
			<text color="#ffffff" font-size={big ? 28 : 16} font-weight={700}>{"Tile " + (i + 1)}</text>
		</view>;

	public static function view():View
		return <view grow={1} padding={20} row-gap={16} font-family="DejaVu Sans" font-size={14} motion="default" motion-color="calm"
			background={dark() ? "#09090b" : "#f4f4f5"} color={dark() ? "#fafafa" : "#18181b"}>
			<view direction="row" column-gap={8} align-items="center">
				<text font-size={22} font-weight={700} grow={1}>Motion</text>
				<Button tag="add" label={() -> "Add"} onPress={add}/>
				<Button tag="remove" label={() -> "Remove"} onPress={removeOne}/>
				<Button tag="shuffle" label={() -> "Shuffle"} onPress={shuffle}/>
				<Button tag="theme" label={() -> dark() ? "Light" : "Dark"} onPress={() -> dark(d -> !d)}/>
				<Button tag="reduce" label={() -> reduced() ? "Full motion" : "Reduced motion"} onPress={() -> setReduced(!reduced())}/>
			</view>
			<view direction="row" column-gap={16} grow={1} min-height={0}>
				<view tag="list" width={260} row-gap={8} padding={12} radius={14} align-items="stretch" lead="snappy" trail="calm"
					background={dark() ? "#18181b" : "#ffffff"}>
					<For each={rows}>{(n:Read<Int>) -> <view tag={"row-" + n()} transition="fade slide-up" direction="row" align-items="center"
						column-gap={10} padding="10 12" radius={10} background={dark() ? "#27272a" : "#f4f4f5"}>
						<view width={10} height={10} radius={5} background={TILES[n() % 4]}/>
						<text grow={1}>{"Row " + n()}</text>
						<text ride="trailing" color={dark() ? "#a1a1aa" : "#71717a"}>{"#" + n()}</text>
					</view>}</For>
				</view>
				<view tag="stage" grow={1} radius={20}>
					<Show when={() -> zoomed() < 0} fallback={<view tag="zoom" grow={1}>{() -> tile(zoomed(), true)}</view>}>
						<view tag="grid" grow={1} row-gap={12} transition="fade scale">
							<view direction="row" grow={1} column-gap={12}>{tile(0, false)}{tile(1, false)}</view>
							<view direction="row" grow={1} column-gap={12}>{tile(2, false)}{tile(3, false)}</view>
						</view>
					</Show>
				</view>
			</view>
		</view>;
}
