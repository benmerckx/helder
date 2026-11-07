import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// A launch dashboard assembling itself: the cards rise in on springs one
// after another, their numbers count up, the traffic chart's bars grow
// (their heights laid out anew, helder.ui.motion springing each), the
// checklist ticks green item by item and the status pill turns from
// staging to live through OKLab.
class Launch implements Markup {
	public static final scene:SceneDef = {name: "launch", title: "A launch, assembling", duration: 7.5, view: view};

	static final KPIS = [
		{label: "Requests / s", value: 48210, unit: "", color: BLUE},
		{label: "p99 latency", value: 112, unit: " ms", color: VIOLET},
		{label: "Error rate", value: 3, unit: "‰", color: CORAL},
		{label: "Regions live", value: 14, unit: " / 14", color: MINT}
	];

	static final CHECKS = ["Build signed", "Migrations applied", "Canary healthy", "Traffic shifted", "Status page updated"];

	static function bar(i:Int):Float {
		var x = i / 23;
		return 0.28 + 0.62 * (0.5 + 0.5 * Math.sin(x * 5.1 + 0.6)) * (0.55 + 0.45 * x) + 0.1 * rand(i);
	}

	static function Kpi(props:{t:Read<Float>, i:Int}):View {
		var k = KPIS[props.i], from = 0.35 + props.i * 0.14;
		return <view tag={"kpi-" + props.i} grow={1} basis={0} padding="18 20" row-gap={10} radius={18} background={PANEL} border-width={1}
			border-color={LINE} transition="fade slide-up(28)" motion="bouncy">
			<view direction="row" align-items="center" column-gap={8}>
				<view width={8} height={8} radius={4} background={k.color}/>
				<text font-size={13} color={MUTED} font-weight={500}>{k.label}</text>
			</view>
			<text font-family="Inter Display" font-size={38} font-weight={650} letter-spacing={-0.8} font-variant-numeric="tabular-nums">{
				thousands(Math.round(k.value * out(lin(props.t(), from + 0.2, from + 1.6)))) + k.unit
			}</text>
			<view height={4} radius={2} background={LINE}>
				<view height={4} radius={2} background={k.color} width={at(props.t(), from + 0.4) ? (70 + props.i * 9) + "%" : "0%"}/>
			</view>
		</view>;
	}

	static function Check(props:{t:Read<Float>, i:Int}):View {
		var when = 2.2 + props.i * 0.55;
		return <view direction="row" align-items="center" column-gap={12} padding="10 12" radius={12}
			background={at(props.t(), when) ? RAISED : PANEL}>
			<view width={22} height={22} radius={11} align-items="center" justify="center" background={at(props.t(), when) ? MINT : LINE}>
				<Show when={() -> at(props.t(), when)}>
					<view transition="pop"><icon name="check" width={14} height={14} color={NIGHT}/></view>
				</Show>
			</view>
			<text grow={1} font-size={15} font-weight={at(props.t(), when) ? 550 : 400} color={at(props.t(), when) ? INK : MUTED}>{CHECKS[props.i]}</text>
			<text font-size={12} color={MUTED} font-variant-numeric="tabular-nums">{at(props.t(), when) ? "0" + (1 + props.i) + ":0" + (2 * props.i + 1) : ""}</text>
		</view>;
	}

	static function countdown(t:Float):String {
		var left = Math.max(0, 5.2 - t);
		return "T−00:00:0" + Std.int(left) + "." + Std.int((left * 10) % 10);
	}

	static function checked(t:Float):Int {
		var n = 0;
		for (i in 0...CHECKS.length)
			if (at(t, 2.2 + i * 0.55)) n++;
		return n;
	}

	public static function view(t:Read<Float>):View {
		var live = () -> at(t(), 5.2);
		return <view grow={1} padding="34 44" row-gap={22} background={NIGHT} color={INK} font-family="Inter" motion="default" motion-color="calm">
			<view direction="row" align-items="center" column-gap={14}>
				<view width={34} height={34} radius={10} background="linear-gradient(135deg, #6d8bff, #a98bff)"/>
				<view row-gap={0}>
					<text font-size={20} font-weight={700} letter-spacing={-0.3}>Orbit</text>
					<text font-size={13} color={MUTED}>Launch control · v4.0</text>
				</view>
				<view grow={1}/>
				<text font-size={15} color={MUTED} font-variant-numeric="tabular-nums">{countdown(t())}</text>
				<view direction="row" align-items="center" column-gap={8} padding="8 16" radius={999} background={live() ? "#0f3b2c" : "#2a2412"}
					border-width={1} border-color={live() ? MINT : AMBER}>
					<view width={8} height={8} radius={4} background={live() ? MINT : AMBER}/>
					<text font-size={14} font-weight={600} color={live() ? MINT : AMBER}>{live() ? "Live" : "Staging"}</text>
				</view>
			</view>
			<view direction="row" column-gap={18} height={150}>
				<Repeat count={4}>{i -> <Show when={() -> at(t(), 0.35 + i * 0.14)}><Kpi t={t} i={i}/></Show>}</Repeat>
			</view>
			<view direction="row" column-gap={18} grow={1} min-height={0}>
				<Show when={() -> at(t(), 0.9)}>
					<view grow={1} padding="20 22" radius={18} background={PANEL} border-width={1} border-color={LINE} row-gap={14} transition="fade slide-up(28)">
						<view direction="row" align-items="baseline" column-gap={10}>
							<text font-size={16} font-weight={600}>Traffic</text>
							<text font-size={13} color={MUTED}>last 24 hours</text>
							<view grow={1}/>
							<text font-size={13} color={MINT} font-weight={600}>{at(t(), 4.2) ? "+38% after shift" : ""}</text>
						</view>
						<view grow={1} direction="row" align-items="end" column-gap={7}>
							<Repeat count={24}>{i -> <view grow={1} basis={0} radius={5} motion="bouncy"
								background={at(t(), 4.2) && i >= 18 ? "linear-gradient(180deg, #3ee0a8, #1d8f6c)" : "linear-gradient(180deg, #6d8bff, #3b4fb8)"}
								height={(at(t(), 1.15 + i * 0.045) ? Math.round(bar(i) * (at(t(), 4.2) && i >= 18 ? 300 : 230)) : 4)}/>}</Repeat>
						</view>
					</view>
				</Show>
				<Show when={() -> at(t(), 1.6)}>
					<view width={380} padding="20 18" radius={18} background={PANEL} border-width={1} border-color={LINE} row-gap={8} transition="fade slide-left(28)">
						<view direction="row" align-items="baseline" padding="0 4 6 4">
							<text grow={1} font-size={16} font-weight={600}>Checklist</text>
							<text font-size={13} color={MUTED} font-variant-numeric="tabular-nums">{checked(t()) + " / " + CHECKS.length}</text>
						</view>
						<Repeat count={5}>{i -> <Check t={t} i={i}/>}</Repeat>
					</view>
				</Show>
			</view>
		</view>;
	}
}
