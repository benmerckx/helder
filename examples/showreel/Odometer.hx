import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// Rolling numbers: each digit a column of 0 to 9 behind a window one
// figure tall, moved to its digit by a transform that springs
// (helder.ui.motion's transform lanes); the columns on the right a little
// quicker than those on the left, so a change ripples across. The figures
// are Inter Display's tabular ones.
class Odometer implements Markup {
	public static final scene:SceneDef = {name: "odometer", title: "Rolling numbers", duration: 6.5, view: view};

	// the revenue at t: steps up every 0.42 s, a big jump at 4.2 s
	static function revenue(t:Float):Int {
		if (t < 0.6) return 1048_210;
		var n = Std.int((t - 0.6) / 0.42), v = 1048_210;
		for (k in 0...n)
			v += 1200 + hash(k) % 23000;
		if (t >= 4.2) v += 61_000;
		return v;
	}

	static function stat(t:Float, k:Int):Int {
		var n = t < 0.8 ? 0 : Std.int((t - 0.8) / (0.55 + 0.1 * k)) + 1;
		return switch k {
			case 0: 18_204 + n * 37 + hash(n) % 29;
			case 1: 982 + n * 3;
			case _: 4_418 + n * 121 + hash(n + 9) % 97;
		}
	}

	// a digit's column: figures stacked, the window on the one shown
	static function Digit(props:{value:Read<Int>, size:Int, place:Int}):View {
		var h = Math.round(props.size * 1.3), v = memo(() -> props.value());
		return <view height={h} overflow="hidden" motion-transform={props.place < 2 ? "snappy" : props.place < 4 ? "default" : "calm"}>
			<view transform={"translate(0px, " + (-v() * h) + "px)"}>
				<Repeat count={10}>{d -> <view height={h} justify="center"><text font-size={props.size} font-family="Inter Display" font-weight={680}
					line-height={1} font-variant-numeric="tabular-nums" letter-spacing={-props.size * 0.02}>{"" + d}</text></view>}</Repeat>
			</view>
		</view>;
	}

	// a number's place (0: units), its comma after it
	static function Place(props:{value:Read<Int>, place:Int, size:Int}):View
		return <view direction="row" align-items="center" overflow="hidden" motion="calm"
			max-width={props.place == 0 || props.value() >= Math.pow(10, props.place) ? props.size : 0}
			opacity={props.place == 0 || props.value() >= Math.pow(10, props.place) ? 1 : 0}>
			<Digit value={() -> Std.int(props.value() / Math.pow(10, props.place)) % 10} size={props.size} place={props.place}/>
			<Show when={props.place > 0 && props.place % 3 == 0}>
				<text font-size={props.size} font-family="Inter Display" font-weight={680} line-height={1}>,</text>
			</Show>
		</view>;

	// a number of so many places, with commas, rolling
	static function Number(props:{value:Read<Int>, places:Int, size:Int, color:String, under:String}):View
		return <view direction="row" align-items="center" color={props.color}>
			<Repeat count={props.places}>{i -> <Place value={props.value} place={props.places - 1 - i} size={props.size}/>}</Repeat>
			<view position="absolute" left={0} right={0} top={0} height={Math.round(props.size * 0.2)} background={"linear-gradient(180deg, " + props.under + ", " + props.under + "00)"}/>
			<view position="absolute" left={0} right={0} bottom={0} height={Math.round(props.size * 0.2)} background={"linear-gradient(0deg, " + props.under + ", " + props.under + "00)"}/>
		</view>;

	static final STATS = [{label: "Orders today", color: BLUE}, {label: "New customers", color: VIOLET}, {label: "Cups of coffee", color: AMBER}];

	public static function view(t:Read<Float>):View {
		return <view grow={1} padding="64 80" background={NIGHT} color={INK} font-family="Inter" justify="center" row-gap={36}>
			<view row-gap={6}>
				<view direction="row" align-items="center" column-gap={12}>
					<text font-size={15} color={MUTED} font-weight={600} letter-spacing={1.6}>REVENUE · THIS QUARTER</text>
					<view padding="4 10" radius={999} background={at(t(), 4.2) ? "#0f3b2c" : RAISED} motion-color="calm">
						<text font-size={13} font-weight={650} color={at(t(), 4.2) ? MINT : MUTED} font-variant-numeric="tabular-nums">{at(t(), 4.2) ? "▲ 12.4% · a big order" : "▲ 6.1%"}</text>
					</view>
				</view>
				<view direction="row" align-items="center" column-gap={6}>
					<text font-family="Inter Display" font-size={150} font-weight={300} color={MUTED} line-height={1}>$</text>
					<Number value={() -> revenue(t())} places={7} size={150} color={INK} under={NIGHT}/>
				</view>
			</view>
			<view direction="row" column-gap={20}>
				<Repeat count={3}>{k -> <view grow={1} basis={0} padding="20 24" radius={18} background={PANEL} border-width={1} border-color={LINE} row-gap={10}>
					<view direction="row" align-items="center" column-gap={8}>
						<view width={8} height={8} radius={4} background={STATS[k].color}/>
						<text font-size={14} color={MUTED} font-weight={500}>{STATS[k].label}</text>
					</view>
					<Number value={() -> stat(t(), k)} places={5} size={48} color={INK} under={PANEL}/>
				</view>}</Repeat>
			</view>
		</view>;
	}
}
