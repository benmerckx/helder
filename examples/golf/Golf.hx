// title: Floating Greens
// summary: Mini golf on floating islands, a small mobile 3D game: drag back from the ball to aim and shoot, orbit and pinch the camera elsewhere; helder.physics at a fixed step, a <Scene> under a HUD and menu in ui, best scores saved
// tags: 3d, game, physics, ui, view, scene markup, touch
// demo: canvas 390x844
import helder.scene.view.SceneTags.*;
import helder.ui.Clock;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The game's window: a sky gradient, the <Scene> filling it (the course,
// drawn by helder.scene; <OrbitControls> for the camera, the shot a
// gesture of the game's on the same box) and the HUD over it in ui's
// markup, clear of the phone's bars (env(safe-area-inset-*)). The game
// steps on ui's clock (Game.frame), its simulation at a fixed rate.
class Golf implements Markup {
	static function main() {
		var game = new Game();
		Clock.add(t -> {
			game.frame(t);
			true;
		});
		UiWindow.run(<Surface title="Floating Greens" width={390} height={844}>
			<view grow={1} background="linear-gradient(180deg, #8ec9ff 0%, #cfe6ff 45%, #ffe3ef 100%)" font-family="DejaVu Sans" color="#2b2d42">
				<Scene grow={1} world={game.world} camera={game.camera} animate setup={game.setup} ref={game.attach}>
					<OrbitControls ref={game.controls}/>
				</Scene>
				<Hud game={game}/>
			</view>
		</Surface>);
	}

	static function Hud(props:{game:Game}):View {
		var g = props.game;
		var hole = memo(() -> Course.holes[g.holeIndex()]);
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none"
			padding-top="calc(env(safe-area-inset-top) + 12px)" padding-bottom="calc(env(safe-area-inset-bottom) + 16px)"
			padding-left="max(16px, env(safe-area-inset-left))" padding-right="max(16px, env(safe-area-inset-right))">
			<view direction="row" align-items="center" justify="space-between">
				<view tag="hole" padding="8 14" radius={18} background="#ffffffd0" shadow="0 2 8 #2b2d4220">
					<text font-size={12} color="#8d99ae">{"HOLE " + (g.holeIndex() + 1)}</text>
					<text font-size={16} font-weight={700}>{hole().name}</text>
				</view>
				<view tag="score" direction="row" column-gap={12} padding="8 14" radius={18} background="#ffffffd0" shadow="0 2 8 #2b2d4220">
					<view align-items="center">
						<text font-size={12} color="#8d99ae">PAR</text>
						<text font-size={18} font-weight={700}>{"" + hole().par}</text>
					</view>
					<view align-items="center">
						<text font-size={12} color="#8d99ae">STROKES</text>
						<text tag="strokes" font-size={18} font-weight={700}>{"" + g.strokes()}</text>
					</view>
				</view>
			</view>
			<view grow={1} align-items="center" justify="center">
				<Show when={g.toast() != ""}>
					<text tag="toast" font-size={18} font-weight={700} color="#ffffff" padding="10 18" radius={20} background="#2b2d42b0">{g.toast()}</text>
				</Show>
			</view>
			<Show when={g.shots() == 0 && g.screen() == "play"}>
				<view align-items="center">
					<text tag="hint" font-size={14} color="#2b2d42" padding="8 16" radius={16} background="#ffffffb0">Drag back from the ball, let go to shoot</text>
				</view>
			</Show>
		</view>;
	}
}
