// title: Motion in TypeScript
// summary: Motion as property tracks from TSX: rows coming and going, a matched zoom, a theme switch, reduced motion
// tags: typescript, ui, view, motion
// demo: canvas 760x520
// examples/motion/Motion.hx in TypeScript: the same attributes (motion,
// transition, matched, lead and trail, ride), declared on the nodes; the
// list moves its rows edge by edge as they come and go, a tile pressed
// flies into the stage and back, the theme's colours move through OKLab,
// Clock.reducedMotion snaps travel and keeps a short fade.
import { signal, For, Show } from "helder/view";
import { UiWindow, Surface, Clock } from "helder/ui";

const rows = signal([1, 2, 3, 4]);
let next = 5;
const dark = signal(false);
const reduced = signal(false);
const zoomed = signal(-1);
const TILES = ["#f97316", "#22c55e", "#3b82f6", "#a855f7"];

function add() {
	rows(rows().concat([next++]));
}

function removeOne() {
	const r = rows();
	if (r.length > 0) rows(r.filter(x => x !== r[r.length > 2 ? 1 : 0]));
}

function shuffle() {
	const r = rows().slice().reverse();
	rows(r.length > 2 ? r.slice(1).concat([r[0]]) : r);
}

function setReduced(on: boolean) {
	reduced(on);
	Clock.reducedMotion = on;
}

function Button(props: { tag: string; label: () => string; onPress: () => void }) {
	return <view:button tag={props.tag} role="button" focusable cursor="pointer" padding="6 12" radius={8}
		background={dark() ? "#27272a" : "#ffffff"} color={dark() ? "#fafafa" : "#18181b"} border-width={1} border-color={dark() ? "#3f3f46" : "#e4e4e7"}
		onPress={() => props.onPress()}>{props.label()}</view:button>;
}

function Tile(props: { i: number; big: boolean }) {
	return <view tag={"tile-" + props.i} matched={"tile-" + props.i} grow={1} radius={props.big ? 28 : 16} background={TILES[props.i]} padding={16}
		cursor="pointer" justify="end" onClick={() => zoomed(props.big ? -1 : props.i)}>
		<text color="#ffffff" font-size={props.big ? 28 : 16} font-weight={700}>{"Tile " + (props.i + 1)}</text>
	</view>;
}

function App() {
	return <view grow={1} padding={20} row-gap={16} font-family="DejaVu Sans" font-size={14} motion="default" motion-color="calm"
		background={dark() ? "#09090b" : "#f4f4f5"} color={dark() ? "#fafafa" : "#18181b"}>
		<view direction="row" column-gap={8} align-items="center">
			<text font-size={22} font-weight={700} grow={1}>Motion</text>
			<Button tag="add" label={() => "Add"} onPress={add}/>
			<Button tag="remove" label={() => "Remove"} onPress={removeOne}/>
			<Button tag="shuffle" label={() => "Shuffle"} onPress={shuffle}/>
			<Button tag="theme" label={() => dark() ? "Light" : "Dark"} onPress={() => dark(d => !d)}/>
			<Button tag="reduce" label={() => reduced() ? "Full motion" : "Reduced motion"} onPress={() => setReduced(!reduced())}/>
		</view>
		<view direction="row" column-gap={16} grow={1} min-height={0}>
			<view tag="list" width={260} row-gap={8} padding={12} radius={14} align-items="stretch" lead="snappy" trail="calm"
				background={dark() ? "#18181b" : "#ffffff"}>
				<For each={rows}>{n => <view tag={"row-" + n()} transition="fade slide-up" direction="row" align-items="center"
					column-gap={10} padding="10 12" radius={10} background={dark() ? "#27272a" : "#f4f4f5"}>
					<view width={10} height={10} radius={5} background={TILES[n() % 4]}/>
					<text grow={1}>{"Row " + n()}</text>
					<text ride="trailing" color={dark() ? "#a1a1aa" : "#71717a"}>{"#" + n()}</text>
				</view>}</For>
			</view>
			<view tag="stage" grow={1} radius={20}>
				<Show when={() => zoomed() < 0} fallback={<view tag="zoom" grow={1}>{() => <Tile i={zoomed()} big={true}/>}</view>}>
					<view tag="grid" grow={1} row-gap={12} transition="fade scale">
						<view direction="row" grow={1} column-gap={12}><Tile i={0} big={false}/><Tile i={1} big={false}/></view>
						<view direction="row" grow={1} column-gap={12}><Tile i={2} big={false}/><Tile i={3} big={false}/></view>
					</view>
				</Show>
			</view>
		</view>
	</view>;
}

UiWindow.run(
	<Surface title="Motion" width={760} height={520}>
		<App/>
	</Surface>
);
