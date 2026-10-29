// title: Floating Greens
// summary: Mini golf on floating islands, a small mobile 3D game: drag back from the ball to aim and shoot, orbit and pinch the camera elsewhere; nine holes on helder.physics at a fixed step, a <Scene> under a HUD and menu in ui, best scores saved
// tags: 3d, game, physics, ui, view, scene markup, touch
// demo: canvas 390x844
import helder.scene.view.SceneTags.*;
import helder.ui.Clock;
import helder.ui.Color;
import helder.ui.StyleSheet;
import helder.ui.Transform;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The game's window: a sky gradient, the <Scene> filling it (the course,
// drawn by helder.scene; <OrbitControls> for the camera, the shot a
// gesture of the game's on the same box) and the HUD over it in ui's
// markup, clear of the phone's bars (env(safe-area-inset-*)): the hole
// and the strokes, a hint, a toast, the card after a hole-in (stars,
// retry, next) and the holes' menu (stars and best strokes, saved). The
// game steps on ui's clock (Game.frame), its simulation at a fixed rate.
class Golf implements Markup {
	static function main() {
		var game = new Game();
		// (natively, GOLF_DEMO=<hole>: its recorded round played, the frames' allocation printed)
		#if (hxmc.target != "wasm32-wasi")
		var demo = Std.parseInt(Sys.getEnv("GOLF_DEMO") ?? "");
		if (demo != null) for (r in GolfReplay.rounds) if (r.hole == demo - 1) game.demo(r.hole, r.shots);
		#end
		Clock.add(t -> {
			game.frame(t);
			true;
		});
		UiWindow.run(<Surface title="Floating Greens" width={390} height={844} theme={sheet}>
			<view grow={1} background="linear-gradient(180deg, #8ec9ff 0%, #cfe6ff 45%, #ffe3ef 100%)" font-family="DejaVu Sans" color="#2b2d42">
				<Scene grow={1} world={game.world} camera={game.camera} animate setup={game.setup} ref={game.attach}>
					<OrbitControls ref={game.controls}/>
				</Scene>
				<Hud game={game}/>
			</view>
		</Surface>);
	}

	// (the pop-ins: from small and clear when first drawn, eased by their transition)
	static final sheet:StyleSheet = {
		rules: [
			{slot: "pop", when: ["starting"], style: {opacity: 0, transform: Transform.parse("scale(0.7)")}},
			{slot: "rise", when: ["starting"], style: {opacity: 0, transform: Transform.parse("translate(0, 24px)")}},
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

	static function Button(props:{label:String, onPress:Void->Void, ?tag:String, ?primary:Bool}):View
		return <view:button tag={props.tag} slot="button" role="button" focusable pointer-events="auto" cursor="pointer" padding="12 22" radius={22}
			background={props.primary == true ? "#ff6b6b" : "#ffffff"} color={props.primary == true ? "#ffffff" : "#2b2d42"} font-size={16} font-weight={700}
			shadow="0 3 10 #2b2d4230" transition="transform 0.12s ease-out" onPress={props.onPress}>{props.label}</view:button>;

	static function Hud(props:{game:Game}):View {
		var g = props.game;
		var hole = memo(() -> Course.holes[g.holeIndex()]);
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none"
			padding-top="calc(env(safe-area-inset-top) + 12px)" padding-bottom="calc(env(safe-area-inset-bottom) + 16px)"
			padding-left="max(16px, env(safe-area-inset-left))" padding-right="max(16px, env(safe-area-inset-right))">
			<view direction="row" align-items="center" justify="space-between">
				<view:button tag="menu" slot="button" role="button" focusable pointer-events="auto" cursor="pointer" direction="row" align-items="center" column-gap={10}
					padding="8 14" radius={18} background="#ffffffd8" shadow="0 2 8 #2b2d4220" transition="transform 0.12s ease-out" onPress={g.openMenu}>
					<text font-size={20} font-weight={700} color="#ff6b6b">{"" + (g.holeIndex() + 1)}</text>
					<view>
						<text font-size={11} color="#8d99ae">{"HOLE " + (g.holeIndex() + 1) + " OF " + Course.holes.length}</text>
						<text font-size={15} font-weight={700}>{hole().name}</text>
					</view>
				</view:button>
				<view tag="score" direction="row" column-gap={14} padding="8 14" radius={18} background="#ffffffd8" shadow="0 2 8 #2b2d4220">
					<view align-items="center">
						<text font-size={11} color="#8d99ae">PAR</text>
						<text font-size={18} font-weight={700}>{"" + hole().par}</text>
					</view>
					<view align-items="center">
						<text font-size={11} color="#8d99ae">STROKES</text>
						<text tag="strokes" font-size={18} font-weight={700} color={g.strokes() > hole().par ? "#e76f51" : "#2b2d42"}>{"" + g.strokes()}</text>
					</view>
				</view>
			</view>
			<view grow={1} align-items="center" justify="center">
				<Show when={g.toast() != ""}>
					<text tag="toast" slot="pop" transition="opacity 0.2s ease-out, transform 0.25s ease-out" font-size={18} font-weight={700} color="#ffffff"
						padding="10 18" radius={20} background="#2b2d42b8">{g.toast()}</text>
				</Show>
				<Show when={g.screen() == "done"}>
					<Card game={g}/>
				</Show>
			</view>
			<Show when={g.screen() == "play"}>
				<view align-items="center" row-gap={8}>
					<Show when={g.aiming()}>
						<view tag="power" width={180} height={10} radius={5} background="#ffffffa0" overflow="hidden">
							<view height={10} radius={5} width={(Math.round(g.power() * 180) : Float)}
								background={powerColor(g.power())}/>
						</view>
					</Show>
					<Show when={g.shots() == 0 && !g.aiming()}>
						<text tag="hint" font-size={14} padding="8 16" radius={16} background="#ffffffc0">Drag back from the ball, let go to shoot</text>
					</Show>
				</view>
			</Show>
			<Show when={g.screen() == "menu"}>
				<Menu game={g}/>
			</Show>
		</view>;
	}

	// after a hole-in: the verdict, the stars, retry and next
	static function Card(props:{game:Game}):View {
		var g = props.game;
		var par = Course.holes[g.holeIndex.peek()].par, strokes = g.strokes.peek();
		var n = stars(strokes, par), best = g.best.peek()[g.holeIndex.peek()];
		return <view tag="card" slot="pop" transition="opacity 0.25s ease-out, transform 0.35s ease-out" pointer-events="auto" align-items="center"
			row-gap={10} padding="22 26" radius={26} background="#fffffff0" shadow="0 8 30 #2b2d4240" min-width={260}>
			<text tag="verdict" font-size={26} font-weight={700} color="#ff6b6b">{verdict(strokes, par)}</text>
			<text tag="stars" font-size={40} color="#ffb703" letter-spacing={6}>{starText(n)}</text>
			<text font-size={14} color="#8d99ae">{strokes + (strokes == 1 ? " stroke" : " strokes") + " · par " + par + " · best " + best}</text>
			<view direction="row" column-gap={12} margin-top={8}>
				<Button tag="retry" label="Retry" onPress={g.retry}/>
				<Button tag="next" label={g.holeIndex.peek() == Course.holes.length - 1 ? "Holes" : "Next hole"} primary
					onPress={() -> g.holeIndex.peek() == Course.holes.length - 1 ? g.openMenu() : g.next()}/>
			</view>
		</view>;
	}

	// every hole: its number, name, par, stars and best; one tapped is played
	static function Menu(props:{game:Game}):View {
		var g = props.game;
		var total = memo(() -> {
			var s = 0;
			for (i in 0...Course.holes.length)
				s += stars(g.best()[i], Course.holes[i].par);
			s;
		});
		return <view tag="holes" position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="auto" background="#2b2d4266"
			padding-top="calc(env(safe-area-inset-top) + 24px)" padding-bottom="calc(env(safe-area-inset-bottom) + 24px)" padding-left={16} padding-right={16}
			align-items="center" justify="center">
			<view slot="rise" transition="opacity 0.25s ease-out, transform 0.3s ease-out" width="100%" max-width={420} padding={18} radius={26}
				background="#fff8f0" row-gap={14} shadow="0 10 40 #2b2d4250">
				<view direction="row" align-items="center" justify="space-between">
					<view>
						<text font-size={24} font-weight={700}>Floating Greens</text>
						<text font-size={13} color="#8d99ae">{total() + " of " + Course.holes.length * 3 + " stars"}</text>
					</view>
					<Button tag="close" label="✕" onPress={g.closeMenu}/>
				</view>
				<view direction="row" wrap justify="space-between" row-gap={10}>
					{[for (i in 0...Course.holes.length) <HoleCard game={g} index={i}/>]}
				</view>
			</view>
		</view>;
	}

	static function HoleCard(props:{game:Game, index:Int}):View {
		var g = props.game, i = props.index, h = Course.holes[props.index];
		return <view:button tag={"hole-" + (i + 1)} slot="button" role="button" focusable cursor="pointer" width="31%" padding="10 6" radius={16}
			align-items="center" row-gap={2} transition="transform 0.12s ease-out"
			background={g.holeIndex() == i ? "#ffe0dc" : "#ffffff"} border-width={2} border-color={g.holeIndex() == i ? "#ff6b6b" : "#ffffff"}
			shadow="0 2 6 #2b2d421a" onPress={() -> g.play(i)}>
			<text font-size={22} font-weight={700} color="#ff6b6b">{"" + (i + 1)}</text>
			<text font-size={11} font-weight={700} text-align="center">{h.name}</text>
			<text font-size={16} color="#ffb703">{starText(stars(g.best()[i], h.par))}</text>
			<text font-size={10} color="#8d99ae">{"par " + h.par + (g.best()[i] > 0 ? " · best " + g.best()[i] : "")}</text>
		</view:button>;
	}
}
