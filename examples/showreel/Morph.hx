import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// A theme switch where everything morphs: four themes, each a set of
// colours, a corner radius and a spacing; switching moves every colour
// through OKLab (text a little ahead, keeping its contrast), every radius
// and every box's edges on springs, the selected theme's marker flying
// to its pill (matched="marker") and the switches' knobs sliding.
typedef Theme = {
	name:String,
	bg:String,
	card:String,
	ink:String,
	muted:String,
	line:String,
	accent:String,
	accentInk:String,
	radius:Int,
	gap:Int,
	pad:Int
}

class Morph implements Markup {
	public static final scene:SceneDef = {name: "theme", title: "A theme, morphing", duration: 7.5, view: view};

	static final THEMES:Array<Theme> = [
		{name: "Daylight", bg: "#eef0f5", card: "#ffffff", ink: "#12141c", muted: "#6b7080", line: "#e2e5ec", accent: "#4f5bff", accentInk: "#ffffff", radius: 16, gap: 20, pad: 22},
		{name: "Midnight", bg: "#090b12", card: "#141824", ink: "#eef1fb", muted: "#8a91a8", line: "#232838", accent: "#8b7bff", accentInk: "#0b0c14", radius: 16, gap: 20, pad: 22},
		{name: "Dusk", bg: "#2b1834", card: "#3d2348", ink: "#ffe9d6", muted: "#c9a3b8", line: "#55325f", accent: "#ff8a65", accentInk: "#2b1834", radius: 30, gap: 26, pad: 28},
		{name: "Paper", bg: "#f3efe6", card: "#fffdf7", ink: "#1f2a24", muted: "#6f7a70", line: "#e0dacb", accent: "#127a5a", accentInk: "#fffdf7", radius: 4, gap: 12, pad: 16}
	];

	// the theme at t
	static function themeAt(t:Float):Int
		return t < 1.2 ? 0 : t < 2.8 ? 1 : t < 4.4 ? 2 : t < 6.0 ? 3 : 1;

	static function Pill(props:{t:Read<Float>, i:Int}):View {
		var th = () -> THEMES[themeAt(props.t())];
		return <view padding="8 16" radius={999} align-items="center" justify="center">
			<Show when={() -> themeAt(props.t()) == props.i}>
				<view matched="marker" position="absolute" left={0} top={0} right={0} bottom={0} radius={999} background={th().accent}/>
			</Show>
			<text font-size={14} font-weight={600} color={themeAt(props.t()) == props.i ? th().accentInk : th().muted}>{THEMES[props.i].name}</text>
		</view>;
	}

	static function Switch(props:{t:Read<Float>, on:Read<Bool>}):View {
		var th = () -> THEMES[themeAt(props.t())];
		return <view width={46} height={28} radius={14} padding={3} direction="row" justify={props.on() ? "end" : "start"}
			background={props.on() ? th().accent : th().line}>
			<view width={22} height={22} radius={11} background="#ffffff" shadow="0 1px 3px rgba(0,0,0,0.25)"/>
		</view>;
	}

	static function Row(props:{t:Read<Float>, label:String, detail:String, on:Read<Bool>}):View {
		var th = () -> THEMES[themeAt(props.t())];
		return <view direction="row" align-items="center" column-gap={12} padding={"" + Math.round(th().gap * 0.55) + " 0"} border-width="0 0 1 0" border-color={th().line}>
			<view grow={1} row-gap={2}>
				<text font-size={15} font-weight={550} color={th().ink}>{props.label}</text>
				<text font-size={13} color={th().muted}>{props.detail}</text>
			</view>
			<Switch t={props.t} on={props.on}/>
		</view>;
	}

	public static function view(t:Read<Float>):View {
		var th = () -> THEMES[themeAt(t())];
		var k = () -> themeAt(t());
		return <view grow={1} padding="40 52" row-gap={28} background={th().bg} color={th().ink} font-family="Inter" motion="default" motion-color="calm">
			<view direction="row" align-items="center">
				<view grow={1} row-gap={2}>
					<text font-family="Inter Display" font-size={32} font-weight={700} letter-spacing={-0.7}>Appearance</text>
					<text font-size={14} color={th().muted}>Colours, corners and spacing, all of them springs</text>
				</view>
				<view direction="row" column-gap={4} padding={4} radius={999} background={th().card} border-width={1} border-color={th().line}>
					<Repeat count={4}>{i -> <Pill t={t} i={i}/>}</Repeat>
				</view>
			</view>
			<view direction="row" grow={1} column-gap={th().gap} min-height={0}>
				<view width={330} padding={th().pad} row-gap={th().gap} radius={th().radius} background={th().card} border-width={1} border-color={th().line}>
					<view direction="row" align-items="center" column-gap={14}>
						<view width={64} height={64} radius={th().radius >= 16 ? 32 : th().radius * 2} background={"linear-gradient(135deg, " + th().accent + ", #ffbf47)"}/>
						<view row-gap={2}>
							<text font-size={19} font-weight={700}>Noor Vandamme</text>
							<text font-size={14} color={th().muted}>@noor · Ghent</text>
						</view>
					</view>
					<view direction="row" column-gap={th().gap}>
						<view grow={1} row-gap={2}><text font-family="Inter Display" font-size={30} font-weight={700} font-variant-numeric="tabular-nums">2,481</text><text font-size={13} color={th().muted}>Followers</text></view>
						<view grow={1} row-gap={2}><text font-family="Inter Display" font-size={30} font-weight={700} font-variant-numeric="tabular-nums">318</text><text font-size={13} color={th().muted}>Following</text></view>
					</view>
					<view grow={1}/>
					<view padding="12 0" radius={Math.min(th().radius, 999)} align-items="center" background={th().accent}>
						<text font-size={15} font-weight={650} color={th().accentInk}>Follow</text>
					</view>
				</view>
				<view grow={1} padding={th().pad} row-gap={th().gap} radius={th().radius} background={th().card} border-width={1} border-color={th().line}>
					<view grow={1} radius={Math.max(2, th().radius - 6)} background={"linear-gradient(160deg, " + th().accent + " 0%, " + th().bg + " 120%)"} justify="end" padding={th().pad}>
						<text font-family="Inter Display" font-size={34} font-weight={700} color="#ffffff" letter-spacing={-0.6}>Slow Tides</text>
						<text font-size={15} color="#ffffffcc">Lowland Hum · 3:41</text>
					</view>
					<view height={6} radius={3} background={th().line}>
						<view height={6} radius={3} background={th().accent} width={(18 + 70 * lin(t(), 0, 7.5)) + "%"}/>
					</view>
					<view direction="row" justify="center" align-items="center" column-gap={28}>
						<image src={icon("skip-back")} width={22} height={22} color={th().ink}/>
						<view width={54} height={54} radius={27} align-items="center" justify="center" background={th().accent}>
							<image src={icon("pause")} width={22} height={22} color={th().accentInk}/>
						</view>
						<image src={icon("skip-forward")} width={22} height={22} color={th().ink}/>
					</view>
				</view>
				<view width={340} padding={th().pad} radius={th().radius} background={th().card} border-width={1} border-color={th().line}>
					<text font-size={16} font-weight={650} padding="0 0 6 0">Preferences</text>
					<Row t={t} label="Sound effects" detail="Clicks and chimes" on={() -> k() == 0 || k() == 3}/>
					<Row t={t} label="Dark interface" detail="Follows the theme" on={() -> k() == 1 || k() == 2}/>
					<Row t={t} label="Rounder corners" detail="Radius by theme" on={() -> THEMES[k()].radius >= 16}/>
					<Row t={t} label="Compact spacing" detail="Tighter rows" on={() -> THEMES[k()].gap < 16}/>
				</view>
			</view>
		</view>;
	}
}
