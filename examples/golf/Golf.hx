// title: Floating Greens
// summary: Mini golf on floating islands, a small mobile 3D game: eighteen holes on three islands, each bringing in its own pieces (bumpers, sand, turnstiles, wind, boosters, lifts, one-way gates, water, portals, switches and their gates, crumbling tiles); drag back from the ball to aim and shoot, orbit and pinch the camera elsewhere; helder.physics at a fixed step, a <Scene hdr> with shadows, bloom and instanced particles under a HUD in ui, best scores saved
// tags: 3d, game, physics, ui, view, scene markup, touch, particles
// demo: canvas 390x844
// apk: android
import helder.scene.view.SceneTags.*;
import helder.ui.Clock;
import helder.ui.StyleSheet;
import helder.ui.Transform;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The game's window: the island's sky (a gradient), the <Scene> filling it
// (the course, drawn by helder.scene in half floats with bloom;
// <OrbitControls> for the camera, the shot a gesture of the game's on the
// same box) and the HUD over it in ui's markup, clear of the phone's bars
// (env(safe-area-inset-*)): the title, the hole's card as the camera flies
// over it, the hole and the strokes, a hint, a toast, the card after a
// hole-in (stars, retry, next), the islands' scorecard (stars and best
// strokes, saved) and a curtain between holes. Set in Fredoka (OFL,
// fonts/), embedded. The game steps on ui's clock (Game.frame), its
// simulation at a fixed rate.
class Golf implements Markup {
	static inline var INK = "#2b2d42";
	static inline var MUTED = "#7d8597";
	static inline var STAR = "#ffb703";

	static function main() {
		Sys.println("floating greens: starting");
		try helder.text.SystemFonts.get().add(helder.asset.Asset.embed("fonts/Fredoka.ttf")) catch (_:Dynamic) {}
		var game = new Game();
		// (GOLF_DEMO=<hole>: its recorded round played, the frames' allocation printed natively)
		#if (hxmc.target != "wasm32-wasi")
		var demo = Std.parseInt(Sys.getEnv("GOLF_DEMO") ?? "");
		if (demo != null) for (r in GolfReplay.rounds) if (r.hole == demo - 1) game.demo(r.hole, r.shots);
		#end
		Clock.add(t -> {
			game.frame(t);
			true;
		});
		UiWindow.run(<Surface title="Floating Greens" width={390} height={844} theme={sheet}>
			<view grow={1} background={game.sky()} font-family="Fredoka" color={INK}>
				<Scene grow={1} world={game.world} camera={game.camera} hdr animate setup={game.setup} ref={game.attach}>
					<OrbitControls ref={game.controls}/>
				</Scene>
				<Hud game={game}/>
				<view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none" background={game.sky()}
					opacity={game.curtain() ? 1.0 : 0.0} transition="opacity 0.28s ease-in-out"/>
			</view>
		</Surface>);
	}

	// (the pop-ins: from small and clear when first drawn, eased by their transition)
	static final sheet:StyleSheet = {
		rules: [
			{slot: "pop", when: ["starting"], style: {opacity: 0, transform: Transform.parse("scale(0.7)")}},
			{slot: "rise", when: ["starting"], style: {opacity: 0, transform: Transform.parse("translate(0, 24px)")}},
			{slot: "drop", when: ["starting"], style: {opacity: 0, transform: Transform.parse("translate(0, -30px)")}},
			{slot: "button", when: ["active"], style: {transform: Transform.parse("scale(0.94)")}},
			{slot: "button", when: ["hover"], style: {opacity: 0.92}}
		]
	};

	// stars for a hole: 3 at par or better, 2 one over, 1 finished, 0 not yet
	public static function stars(strokes:Int, par:Int):Int
		return strokes <= 0 ? 0 : strokes <= par ? 3 : strokes == par + 1 ? 2 : 1;

	static function starText(n:Int):String
		return [for (i in 0...3) i < n ? "★" : "☆"].join("");

	// the name of a score against par
	static function verdict(strokes:Int, par:Int):String
		return if (strokes == 1) "Hole in one!" else switch strokes - par {
			case -3: "Albatross!";
			case -2: "Eagle!";
			case -1: "Birdie!";
			case 0: "Par";
			case 1: "Bogey";
			case 2: "Double bogey";
			case d: '+$d';
		}

	static function powerColor(p:Float):String
		return p < 0.6 ? "#ffd166" : p < 0.9 ? "#f4a261" : "#ff6b6b";

	static function hex(c:Int):String
		return "#" + StringTools.hex(c, 6);

	static function accent(i:Int):String
		return hex(Course.worlds[Course.holes[i].world].accent);

	static function Button(props:{label:String, onPress:Void->Void, ?tag:String, ?primary:Bool, ?color:String, ?wide:Bool}):View {
		var bg = props.primary == true ? (props.color ?? "#ff6b6b") : "#ffffff";
		return <view:button tag={props.tag} slot="button" role="button" focusable pointer-events="auto" cursor="pointer" padding="13 24" radius={24}
			min-width={props.wide == true ? 180 : 0} align-items="center" background={bg} color={props.primary == true ? "#ffffff" : INK} font-size={17}
			font-weight={600} shadow="0 4 14 #2b2d4230" transition="transform 0.12s ease-out" onPress={props.onPress}>{props.label}</view:button>;
	}

	static function Hud(props:{game:Game}):View {
		var g = props.game;
		var hole = memo(() -> Course.holes[g.holeIndex()]);
		var world = memo(() -> Course.worlds[hole().world]);
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none"
			padding-top="calc(env(safe-area-inset-top) + 12px)" padding-bottom="calc(env(safe-area-inset-bottom) + 16px)"
			padding-left="max(14px, env(safe-area-inset-left))" padding-right="max(14px, env(safe-area-inset-right))">
			<Show when={g.screen() != "title"}>
				<view direction="row" align-items="flex-start" justify="space-between" column-gap={8}>
					<view:button tag="menu" slot="button" role="button" focusable pointer-events="auto" cursor="pointer" direction="row" align-items="center"
						column-gap={10} padding="6 14 6 6" radius={24} background="#ffffffe0" shadow="0 3 10 #2b2d4224" transition="transform 0.12s ease-out"
						onPress={g.openMenu}>
						<view width={36} height={36} radius={18} background={accent(g.holeIndex())} align-items="center" justify="center">
							<text font-size={18} font-weight={700} color="#ffffff">{"" + (g.holeIndex() + 1)}</text>
						</view>
						<view>
							<text font-size={11} font-weight={500} color={MUTED} letter-spacing={1}>{world().name.toUpperCase()}</text>
							<text font-size={17} font-weight={600}>{hole().name}</text>
						</view>
					</view:button>
					<view tag="score" direction="row" column-gap={14} padding="6 16" radius={24} background="#ffffffe0" shadow="0 3 10 #2b2d4224">
						<view align-items="center">
							<text font-size={11} font-weight={500} color={MUTED} letter-spacing={1}>PAR</text>
							<text font-size={20} font-weight={700}>{"" + hole().par}</text>
						</view>
						<view width={1} background="#2b2d421c"/>
						<view align-items="center">
							<text font-size={11} font-weight={500} color={MUTED} letter-spacing={1}>STROKES</text>
							<text tag="strokes" font-size={20} font-weight={700} color={g.strokes() > hole().par ? "#e76f51" : INK}>{"" + g.strokes()}</text>
						</view>
					</view>
				</view>
			</Show>
			<view grow={1} align-items="center" justify="center">
				<Show when={g.card() && g.screen() == "play"}>
					<HoleCard game={g}/>
				</Show>
				<Show when={g.toast() != ""}>
					<text tag="toast" slot="pop" transition="opacity 0.2s ease-out, transform 0.25s ease-out" font-size={20} font-weight={600} color="#ffffff"
						padding="10 20" radius={22} background="#2b2d42c0">{g.toast()}</text>
				</Show>
			</view>
			<Show when={g.screen() == "done"}>
				<view align-items="center"><Done game={g}/></view>
			</Show>
			<Show when={g.screen() == "play"}>
				<view align-items="center" row-gap={8}>
					<Show when={g.aiming()}>
						<view tag="power" width={220} height={14} radius={7} background="#ffffffa8" overflow="hidden" shadow="0 2 8 #2b2d4220">
							<view height={14} radius={7} width={(Math.round(g.power() * 220) : Float)} background={powerColor(g.power())}/>
						</view>
					</Show>
					<Show when={g.shots() == 0 && !g.aiming() && !g.card()}>
						<text tag="hint" font-size={15} font-weight={500} padding="9 18" radius={18} background="#ffffffd0">Drag back from the ball, let go to shoot</text>
					</Show>
				</view>
			</Show>
			<Show when={g.screen() == "title"}>
				<Title game={g}/>
			</Show>
			<Show when={g.screen() == "menu"}>
				<Menu game={g}/>
			</Show>
		</view>;
	}

	// the title over the hole turning slowly behind it
	static function Title(props:{game:Game}):View {
		var g = props.game;
		var total = memo(() -> {
			var s = 0;
			for (i in 0...Course.holes.length)
				s += stars(g.best()[i], Course.holes[i].par);
			s;
		});
		return <view tag="title" position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none" align-items="center" justify="space-between"
			padding-top="calc(env(safe-area-inset-top) + 64px)" padding-bottom="calc(env(safe-area-inset-bottom) + 48px)" padding-left={20} padding-right={20}>
			<view slot="drop" transition="opacity 0.5s ease-out, transform 0.6s ease-out" align-items="center" row-gap={4}>
				<text font-size={g.wide() ? 64 : 46} font-weight={700} color="#ffffff" text-align="center" text-shadow="0 3 0 #2b2d4240">Floating Greens</text>
				<text font-size={17} font-weight={500} color="#ffffff" text-align="center" text-shadow="0 1 0 #2b2d4240">Mini golf on three islands in the sky</text>
			</view>
			<view slot="rise" transition="opacity 0.5s ease-out, transform 0.6s ease-out" align-items="center" row-gap={12}>
				<Button tag="play" label={g.best()[0] > 0 ? "Play hole " + (g.holeIndex() + 1) : "Play"} primary wide onPress={g.start}/>
				<Button tag="holes" label="Holes" wide onPress={g.openMenu}/>
				<text font-size={14} font-weight={500} color="#ffffff" text-shadow="0 1 0 #2b2d4240">
					{total() + " of " + Course.holes.length * 3 + " stars · 18 holes"}</text>
			</view>
		</view>;
	}

	// the hole's card as the camera flies over it: its number and name, par, what it brings in
	static function HoleCard(props:{game:Game}):View {
		var g = props.game;
		var i = g.holeIndex.peek(), h = Course.holes[i], w = Course.worlds[h.world];
		return <view tag="card" slot="pop" transition="opacity 0.3s ease-out, transform 0.4s ease-out" align-items="center" row-gap={6} padding="18 26"
			radius={26} background="#ffffffeb" shadow="0 10 30 #2b2d4235" max-width={340} margin-bottom={120}>
			<text font-size={12} font-weight={600} color={hex(w.accent)} letter-spacing={2}>{"HOLE " + (i + 1) + " · " + w.name.toUpperCase()}</text>
			<text font-size={32} font-weight={700} text-align="center">{h.name}</text>
			<view direction="row" column-gap={8} align-items="center">
				<text font-size={15} font-weight={600} padding="3 12" radius={12} background="#2b2d420f">{"Par " + h.par}</text>
			</view>
			<Show when={(h.tip ?? "") != ""}>
				<text font-size={15} font-weight={500} color={MUTED} text-align="center" margin-top={2}>{h.tip ?? ""}</text>
			</Show>
		</view>;
	}

	// after a hole-in: the verdict, the stars, retry and next
	static function Done(props:{game:Game}):View {
		var g = props.game;
		var i = g.holeIndex.peek();
		var par = Course.holes[i].par, strokes = g.strokes.peek();
		var n = stars(strokes, par), best = g.best.peek()[i];
		var last = i == Course.holes.length - 1;
		var islandEnd = i % 6 == 5;
		return <view tag="done" slot="pop" transition="opacity 0.25s ease-out, transform 0.35s ease-out" pointer-events="auto" align-items="center"
			row-gap={8} padding="22 26" radius={28} background="#fffffff2" shadow="0 10 34 #2b2d4245" min-width={280}>
			<text tag="verdict" font-size={30} font-weight={700} color={accent(i)}>{verdict(strokes, par)}</text>
			<text tag="stars" font-size={42} color={STAR} letter-spacing={6} font-family="DejaVu Sans">{starText(n)}</text>
			<text font-size={15} font-weight={500} color={MUTED}>{strokes + (strokes == 1 ? " stroke" : " strokes") + " · par " + par + " · best " + best}</text>
			<Show when={islandEnd}>
				<text font-size={15} font-weight={600} color={accent(i)}>{Course.worlds[Course.holes[i].world].name + (last ? " done: the course is yours" : " done!")}</text>
			</Show>
			<view direction="row" column-gap={12} margin-top={8}>
				<Button tag="retry" label="Retry" onPress={g.retry}/>
				<Button tag="next" label={last ? "Scorecard" : islandEnd ? "Next island" : "Next hole"} primary color={accent(i)}
					onPress={() -> last ? g.openMenu() : g.next()}/>
			</view>
		</view>;
	}

	// the scorecard: every island's holes, each with its par, stars and best; one tapped is played
	static function Menu(props:{game:Game}):View {
		var g = props.game;
		var total = memo(() -> {
			var s = 0;
			for (i in 0...Course.holes.length)
				s += stars(g.best()[i], Course.holes[i].par);
			s;
		});
		return <view tag="holes" position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="auto" background="#1b1d2e70"
			padding-top="calc(env(safe-area-inset-top) + 16px)" padding-bottom="calc(env(safe-area-inset-bottom) + 16px)" padding-left={12} padding-right={12}
			align-items="center" justify="center">
			<view slot="rise" transition="opacity 0.25s ease-out, transform 0.3s ease-out" width="100%" max-width={g.wide() ? 880 : 460} max-height="100%"
				padding={16} radius={28} background="#fff8f0" row-gap={10} shadow="0 12 44 #2b2d4250">
				<view direction="row" align-items="center" justify="space-between">
					<view>
						<text font-size={26} font-weight={700}>Scorecard</text>
						<text font-size={14} font-weight={500} color={MUTED}>{total() + " of " + Course.holes.length * 3 + " stars"}</text>
					</view>
					<Button tag="close" label="Close" onPress={g.closeMenu}/>
				</view>
				<scroll grow={1} min-height={0} row-gap={12}>
					{[for (w in 0...Course.worlds.length) <Island game={g} index={w}/>]}
				</scroll>
			</view>
		</view>;
	}

	static function Island(props:{game:Game, index:Int}):View {
		var g = props.game, w = Course.worlds[props.index];
		var holes = [for (i in 0...Course.holes.length) if (Course.holes[i].world == props.index) i];
		var summary = memo(() -> {
			var s = 0, par = 0, strokes = 0, done = 0;
			for (i in holes) {
				var b = g.best()[i];
				s += stars(b, Course.holes[i].par);
				par += Course.holes[i].par;
				if (b > 0) {
					strokes += b;
					done++;
				}
			}
			var score = done == holes.length ? " · " + strokes + " for par " + par : " · par " + par;
			s + " of " + holes.length * 3 + " stars" + score;
		});
		return <view row-gap={8}>
			<view direction="row" align-items="center" column-gap={10}>
				<view width={6} height={30} radius={3} background={hex(w.accent)}/>
				<view grow={1}>
					<text font-size={18} font-weight={700}>{w.name}</text>
					<text font-size={12} font-weight={500} color={MUTED}>{w.blurb + " · " + summary()}</text>
				</view>
			</view>
			<view direction="row" wrap justify="space-between" row-gap={8}>
				{[for (i in holes) <HoleTile game={g} index={i}/>]}
			</view>
		</view>;
	}

	static function HoleTile(props:{game:Game, index:Int}):View {
		var g = props.game, i = props.index, h = Course.holes[props.index];
		var color = hex(Course.worlds[h.world].accent);
		return <view:button tag={"hole-" + (i + 1)} slot="button" role="button" focusable cursor="pointer" width={g.wide() ? "15.8%" : "31.8%"}
			padding="8 4" radius={16} align-items="center" row-gap={1} transition="transform 0.12s ease-out"
			background={g.holeIndex() == i ? "#ffffff" : "#ffffffb0"} border-width={2} border-color={g.holeIndex() == i ? color : "#ffffff00"}
			shadow="0 2 6 #2b2d4218" onPress={() -> g.go(i)}>
			<text font-size={20} font-weight={700} color={color}>{"" + (i + 1)}</text>
			<text font-size={12} font-weight={600} text-align="center">{h.name}</text>
			<text font-size={15} color={STAR} font-family="DejaVu Sans">{starText(stars(g.best()[i], h.par))}</text>
			<text font-size={11} font-weight={500} color={MUTED}>{"par " + h.par + (g.best()[i] > 0 ? " · best " + g.best()[i] : "")}</text>
		</view:button>;
	}
}
