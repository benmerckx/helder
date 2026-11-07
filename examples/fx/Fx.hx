// title: Effects
// summary: An effects gallery: liquid metal, glass and frost, glow, fire, a mesh gradient, grain, dither and electric arcs, each a small shader definition with four knobs and two colours (a uniform block), and a neon sign drawn with helder.canvas's filters; opened with a matched zoom, tuned by sliders or the keyboard, still under reduced motion
// tags: gfx, shaders, canvas, ui, motion, showcase
// demo: canvas 1280x720
import Effects;
import FxBox;
import helder.gfx.shader.Vec4;
import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

typedef Effect = {
	id:String,
	name:String,
	blurb:String,
	knobs:Array<String>,
	values:Array<Float>,
	a:String,
	b:String,
	// the time its reduced-motion still shows (s)
	still:Float,
	shader:Null<FxShader>
}

// The gallery: nine effects in a grid, each drawing live; one pressed (or
// Enter on the focused one) flies open (matched="fx-<n>") beside its
// knobs, which the pointer drags or the arrows turn (Up and Down pick one,
// Left and Right move it), Escape flies it back. Under reduced motion each
// shows its still. Effects.hx holds the shaders, FxBox draws one in ui's
// layout, Neon.hx is the canvas piece.
//
//   helder run examples/fx
//   helder run --headless examples/fx --video fx.mp4 --duration 24 -- --tour
//   helder run --headless examples/fx --snap fire.png --at 2 -- --effect fire
class Fx implements Markup {
	public static final EFFECTS:Array<Effect> = [
		{id: "metal", name: "Liquid metal", blurb: "Noise folded into itself twice, then into the bands of polished chrome; two colours caught in its dips and highlights.",
			knobs: ["Speed", "Scale", "Warp", "Shine"], values: [0.3, 0.35, 0.55, 0.4], a: "#5468ff", b: "#ffd29a", still: 4.0, shader: MetalShader},
		{id: "frost", name: "Glass and frost", blurb: "A pane over drifting lights: what is behind it bent by its noise, spread over five taps and milked; its edge catches the light.",
			knobs: ["Frost", "Refraction", "Milk", "Rim"], values: [0.45, 0.4, 0.4, 0.5], a: "#ff6f91", b: "#6d8bff", still: 2.0, shader: FrostShader},
		{id: "glow", name: "Glow", blurb: "A ring of light falling off as one over the distance, two colours turning around it, sparks circling.",
			knobs: ["Radius", "Bloom", "Swirl", "Sparks"], values: [0.5, 0.45, 0.3, 0.5], a: "#a98bff", b: "#3ee0ff", still: 1.3, shader: GlowShader},
		{id: "fire", name: "Fire", blurb: "Two octaves of noise rising through a flame's outline, its heat mapped from black through red and orange to white.",
			knobs: ["Speed", "Turbulence", "Height", "Tint"], values: [0.35, 0.45, 0.6, 0.0], a: "#6d8bff", b: "#ffffff", still: 2.4, shader: FireShader},
		{id: "mesh", name: "Mesh gradient", blurb: "Four colours at points that drift, mixed by their inverse distances over a gently warped plane.",
			knobs: ["Speed", "Softness", "Warp", "Grain"], values: [0.3, 0.4, 0.4, 0.5], a: "#ff6f91", b: "#4b6bff", still: 3.0, shader: MeshShader},
		{id: "grain", name: "Grain", blurb: "A soft gradient and its sun under film grain that changes every frame; its size and amount are knobs.",
			knobs: ["Amount", "Size", "Sun", "-"], values: [0.4, 0.2, 0.5, 0.0], a: "#1b2a6b", b: "#ff9a62", still: 2.0, shader: GrainShader},
		{id: "dither", name: "Dither", blurb: "A lit sphere and a wave behind it, in a handful of levels of two colours, ordered by Bayer's thresholds.",
			knobs: ["Pixel", "Levels", "-", "-"], values: [0.3, 0.2, 0.0, 0.0], a: "#14152b", b: "#c8f560", still: 1.0, shader: DitherShader},
		{id: "electric", name: "Electric", blurb: "Arcs between two points, each a line displaced by noise that changes many times a second, a white core in a coloured glow.",
			knobs: ["Flicker", "Detail", "Reach", "Ends"], values: [0.4, 0.5, 0.5, 0.4], a: "#4cc9ff", b: "#a98bff", still: 1.7, shader: ElectricShader},
		{id: "neon", name: "Neon, on canvas", blurb: "helder.canvas on the CPU: the tube's strokes in layers blurred by its filters, the hue turned by a colour matrix, flickering.",
			knobs: ["Glow", "Hue", "Flicker", "Wall"], values: [0.5, 0.0, 0.3, 0.4], a: "#3ee0ff", b: "#ffffff", still: 0.0, shader: null}
	];

	static final clock:Signal<Float> = signal(0.0);
	static final open:Signal<Int> = signal(-1);
	static final focus:Signal<Int> = signal(0);
	static final knob:Signal<Int> = signal(0);
	static final values:Array<Signal<Array<Float>>> = [for (e in EFFECTS) signal(e.values.copy())];

	static inline var NIGHT = "#07080d";
	static inline var PANEL = "#10121a";
	static inline var LINE = "#252a3a";
	static inline var INK = "#f2f4fb";
	static inline var MUTED = "#8a91a8";
	static inline var ACCENT = "#6d8bff";

	static function vec(hex:String):Vec4 {
		var c = helder.ui.Color.parse(hex);
		return new Vec4(c.r / 255, c.g / 255, c.b / 255, 1);
	}

	// the effect's time: the clock's, or its still under reduced motion
	static function timeOf(i:Int):Float
		return Clock.reducedMotion ? EFFECTS[i].still : clock();

	// an effect drawing in a box of the layout
	static function Live(props:{i:Int}):helder.ui.Node {
		var e = EFFECTS[props.i];
		var a = vec(e.a), b = vec(e.b);
		if (e.shader == null) {
			var n = new Neon();
			n.style.grow = 1;
			renderEffect(() -> values[props.i](), v -> n.setKnobs(v));
			renderEffect(() -> timeOf(props.i), t -> {
				n.time = t;
				if (n.ui != null) n.ui.requestFrame();
			});
			return n;
		}
		var n = new FxBox(e.shader);
		n.style.grow = 1;
		n.a = a;
		n.b = b;
		renderEffect(() -> values[props.i](), v -> n.setKnobs(v));
		renderEffect(() -> timeOf(props.i), t -> {
			n.time = t;
			if (n.ui != null) n.ui.requestFrame();
		});
		return n;
	}

	static function Tile(props:{i:Int}):View
		return <view grow={1} basis={0} min-width={0} row-gap={8} cursor="pointer" onClick={() -> {
			focus(props.i);
			open(props.i);
		}}>
			<view tag={"fx-" + props.i} matched={"fx-" + props.i} grow={1} min-height={0} radius={14} overflow="hidden" border-width={2}
				border-color={focus() == props.i ? ACCENT : "#00000000"}>
				<Live i={props.i}/>
			</view>
			<view direction="row" align-items="baseline">
				<text grow={1} font-size={14} font-weight={600}>{EFFECTS[props.i].name}</text>
				<text font-size={12} color={MUTED}>{EFFECTS[props.i].shader == null ? "helder.canvas" : "shader"}</text>
			</view>
		</view>;

	static function Grid():View
		return <view grow={1} row-gap={18} transition="fade">
			<Repeat count={3}>{r -> <view direction="row" grow={1} basis={0} min-height={0} column-gap={18}>
				<Repeat count={3}>{c -> <Tile i={r * 3 + c}/>}</Repeat>
			</view>}</Repeat>
		</view>;

	static function set(i:Int, k:Int, v:Float) {
		var next = values[i]().copy();
		next[k] = Math.max(0, Math.min(1, v));
		values[i](next);
	}

	static function Slider(props:{i:Int, k:Int}):View {
		var e = EFFECTS[props.i];
		var dragging = false;
		var at = (x:Float, w:Float) -> set(props.i, props.k, x / Math.max(1, w));
		return <view row-gap={8} opacity={e.knobs[props.k] == "-" ? 0.35 : 1}>
			<view direction="row">
				<text grow={1} font-size={14} font-weight={knob() == props.k ? 650 : 450} color={knob() == props.k ? INK : MUTED}>{e.knobs[props.k]}</text>
				<text font-size={13} color={MUTED} font-variant-numeric="tabular-nums">{Std.string(Math.round(values[props.i]()[props.k] * 100)) + "%"}</text>
			</view>
			<view tag={"knob-" + props.k} height={22} justify="center" cursor="pointer" onPointerDown={e -> {
				dragging = true;
				knob(props.k);
				e.current.capture();
				at(e.localX, e.current.width);
			}} onPointerMove={e -> if (dragging) at(e.localX, e.current.width)} onPointerUp={_ -> dragging = false} onPointerCancel={_ -> dragging = false}>
				<view height={4} radius={2} background={LINE}>
					<view height={4} radius={2} background={knob() == props.k ? ACCENT : "#5a6280"} width={(values[props.i]()[props.k] * 100) + "%"}/>
				</view>
				<view position="absolute" top={3} left={"calc(" + (values[props.i]()[props.k] * 100) + "% - 8px)"} width={16} height={16} radius={8}
					background={INK} shadow="0 1px 4px rgba(0,0,0,0.5)"/>
			</view>
		</view>;
	}

	static function Detail(props:{i:Int}):View {
		var e = EFFECTS[props.i];
		return <view grow={1} direction="row" column-gap={32}>
			<view tag={"fx-" + props.i} matched={"fx-" + props.i} grow={1} radius={22} overflow="hidden"><Live i={props.i}/></view>
			<view width={320} row-gap={14} justify="center" transition="fade slide-left(32)">
				<text font-size={13} color={MUTED} font-weight={600} letter-spacing={1.6}>{"EFFECT " + (props.i + 1) + " OF " + EFFECTS.length}</text>
				<text font-size={36} font-weight={700} letter-spacing={-0.8}>{e.name}</text>
				<text font-size={15} color={MUTED} line-height={1.5}>{e.blurb}</text>
				<view height={1} background={LINE} margin="6 0"/>
				<Repeat count={4}>{k -> <Slider i={props.i} k={k}/>}</Repeat>
				<view direction="row" column-gap={10} align-items="center" padding="6 0 0 0">
					<view width={22} height={22} radius={11} background={e.a} border-width={1} border-color={LINE}/>
					<view width={22} height={22} radius={11} background={e.b} border-width={1} border-color={LINE}/>
					<text font-size={13} color={MUTED}>its two colours</text>
				</view>
				<text font-size={12} color={MUTED} padding="10 0 0 0">↑ ↓ a knob · ← → turn it · Esc back</text>
			</view>
		</view>;
	}

	static function key(e:helder.ui.Event) {
		var o = open();
		switch e.key {
			case Key.ESCAPE if (o >= 0):
				open(-1);
			case Key.ENTER | Key.SPACE if (o < 0):
				open(focus());
			case Key.LEFT if (o < 0):
				focus((focus() + EFFECTS.length - 1) % EFFECTS.length);
			case Key.RIGHT if (o < 0):
				focus((focus() + 1) % EFFECTS.length);
			case Key.UP if (o < 0):
				focus((focus() + EFFECTS.length - 3) % EFFECTS.length);
			case Key.DOWN if (o < 0):
				focus((focus() + 3) % EFFECTS.length);
			case Key.UP:
				knob((knob() + 3) % 4);
			case Key.DOWN:
				knob((knob() + 1) % 4);
			case Key.LEFT:
				set(o, knob(), values[o]()[knob()] - 0.05);
			case Key.RIGHT:
				set(o, knob(), values[o]()[knob()] + 0.05);
			case _:
				return;
		}
		e.preventDefault();
	}

	public static function view():View
		return <view tag="fx" grow={1} padding="32 40" row-gap={20} background={NIGHT} color={INK} font-family="Inter" motion="default" focusable
			onKeyDown={key} ref={n -> root = n}>
			<view direction="row" align-items="baseline" column-gap={14}>
				<text font-size={30} font-weight={700} letter-spacing={-0.6}>Effects</text>
				<text font-size={15} color={MUTED} grow={1}>shader definitions with knobs, and a canvas with filters</text>
				<text font-size={13} color={MUTED}>{Clock.reducedMotion ? "reduced motion: stills" : open() < 0 ? "Enter opens · arrows move" : ""}</text>
			</view>
			<view grow={1} min-height={0}>
				<Show when={() -> open() < 0} fallback={<view grow={1}>{() -> <Detail i={open()}/>}</view>}>
					{Grid()}
				</Show>
			</view>
		</view>;

	static var root:Null<helder.ui.Node> = null;

	// --tour: the gallery, then each effect opened in turn, a knob swept, and back
	static function tour(t:Float) {
		var at = t - 1.5;
		if (at < 0) return;
		var k = Std.int(at / 2.6), into = at - k * 2.6;
		if (k >= EFFECTS.length) {
			if (open() != -1) open(-1);
			return;
		}
		var want = into < 2.2 ? k : -1;
		if (focus() != k) focus(k);
		if (open() != want) open(want);
		if (want >= 0 && into > 0.6) {
			var e = EFFECTS[k], v = e.values[0] + 0.35 * Math.sin((into - 0.6) * 2.4);
			knob(0);
			set(k, 0, v);
		}
	}

	static function main() {
		var f = helder.text.SystemFonts.get();
		try f.add(helder.asset.Asset.embed("fonts/Inter.ttf")) catch (_:Dynamic) {}
		var args = Sys.args(), touring = args.indexOf("--tour") >= 0;
		var k = args.indexOf("--effect");
		if (k >= 0 && k + 1 < args.length) for (i in 0...EFFECTS.length) if (EFFECTS[i].id == args[k + 1]) {
			focus(i);
			open(i);
		}
		var start = -1.0, focused = false;
		Clock.add(now -> {
			if (start < 0) start = now;
			clock(now - start);
			if (touring) tour(now - start);
			if (!focused && root != null && root.ui != null) {
				focused = true;
				root.focus(false);
			}
			true;
		});
		UiWindow.run(<Surface title="Effects" width={1280} height={720} background={NIGHT}>{view()}</Surface>);
	}
}
