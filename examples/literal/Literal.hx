// title: Taken literally
// summary: A preferences panel where every setting does exactly what it says: Gravity drops the controls into a pile, Night shift sets the sun and lights the stars, Freeze frosts the glass and slows every spring, Shuffle shuffles, Right to left flips the panel; all of it motion declared on the nodes
// tags: ui, view, motion, canvas, playful, showcase
// demo: canvas 1280x720
import haxe.io.Bytes;
import helder.canvas.Canvas;
import helder.canvas.Filter;
import helder.canvas.Paint;
import helder.canvas.Path;
import helder.canvas.Stroke;
import helder.image.Image;
import helder.ui.Clock;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The settings are signals; what each does is the panel's markup reading
// them, and helder.ui.motion moving the nodes there:
//
// - Gravity: each row's transform drops it to the panel's floor, turned a
//   little, onto the ones below (a bouncy spring); drawn and hit where it
//   lands, so its switch still turns it off.
// - Night shift: the sky's colours move through OKLab to the night's, the
//   sun sets behind the hills and the moon rises, the stars come out, the
//   panel goes dark.
// - Freeze: frost (crystals grown on helder.canvas once, blurred) creeps
//   over the glass, and the panel's motion becomes a slow, heavy spring:
//   everything that moves after it moves frozen.
// - Shuffle: the rows are put in another order (keyed rows, laid out anew).
// - Right to left: the panel's direction (dir="rtl"), every row mirrored.
//
// examples/literal/demo.json presses them in turn (helder run --headless
// examples/literal --script examples/literal/demo.json --pointer --video ...).
class Literal implements Markup {
	static final gravity = signal(false);
	static final night = signal(false);
	static final freeze = signal(false);
	static final shuffle = signal(false);
	static final rtl = signal(false);

	static final ROWS:Array<{id:String, label:String, detail:String, tint:String, icon:String, on:Signal<Bool>}> = [
		{id: "gravity", label: "Gravity", detail: "Pulls things down", tint: "#ff6f91", icon: '<path d="M12 17V3"/><path d="m6 11 6 6 6-6"/><path d="M19 21H5"/>', on: gravity},
		{id: "night", label: "Night shift", detail: "Warmer after sunset", tint: "#7c6cff", icon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>', on: night},
		{id: "freeze", label: "Freeze", detail: "Keeps everything still", tint: "#38bdf8",
			icon: '<line x1="2" x2="22" y1="12" y2="12"/><line x1="12" x2="12" y1="2" y2="22"/><path d="m20 16-4-4 4-4"/><path d="m4 8 4 4-4 4"/><path d="m16 4-4 4-4-4"/><path d="m8 20 4-4 4 4"/>',
			on: freeze},
		{id: "shuffle", label: "Shuffle", detail: "Plays in a random order", tint: "#f59e0b",
			icon: '<path d="m18 14 4 4-4 4"/><path d="m18 2 4 4-4 4"/><path d="M2 18h1.4c1.3 0 2.5-.6 3.3-1.7l6.1-8.6c.7-1.1 2-1.7 3.3-1.7H22"/><path d="M2 6h1.9c1.5 0 2.9.9 3.6 2.2"/><path d="M22 18h-5.9c-1.3 0-2.6-.7-3.3-1.8l-.5-.8"/>',
			on: shuffle},
		{id: "rtl", label: "Right to left", detail: "For Arabic and Hebrew", tint: "#22c55e",
			icon: '<path d="M8 3 4 7l4 4"/><path d="M4 7h16"/><path d="m16 21 4-4-4-4"/><path d="M20 17H4"/>', on: rtl}
	];

	static inline var ROW = 72;
	static inline var HEAD = 104;
	static inline var PANEL_H = 560;
	static final TILT = [-5.0, 7.0, -9.0, 4.0, -2.5];
	static final SLIDE = [-34.0, 26.0, -12.0, 40.0, -4.0];

	static final svgs = new Map<String, helder.ui.Svg>();

	static function icon(markup:String):helder.ui.Svg {
		var s = svgs.get(markup);
		if (s == null) svgs.set(markup, s = helder.ui.Svg.parse(helder.ui.widgets.Icons.OPEN + markup + "</svg>"));
		return s;
	}

	// the rows' order
	static function order():Array<Int>
		return shuffle() ? [3, 0, 4, 1, 2] : [0, 1, 2, 3, 4];

	// where a row falls to under gravity: its place in the pile at the floor
	static function fall(i:Int):String {
		if (!gravity()) return "none";
		var place = order().indexOf(i), top = HEAD + place * ROW;
		var land = PANEL_H - 22 - (ROWS.length - place) * (ROW - 10);
		return "translate(" + SLIDE[i] + "px, " + (land - top) + "px) rotate(" + TILT[i] + "deg)";
	}

	static function Switch(props:{on:Read<Bool>, tint:String}):View
		return <view width={50} height={30} radius={15} padding={3} direction="row" justify={props.on() ? "end" : "start"}
			background={props.on() ? props.tint : night() ? "#2a3048" : "#d9dce5"}>
			<view width={24} height={24} radius={12} background="#ffffff" shadow="0 1px 3px rgba(0,0,0,0.3)"/>
		</view>;

	static function Row(props:{i:Int}):View {
		var r = ROWS[props.i];
		return <view tag={r.id} role="switch" label={r.label} checked={r.on()} focusable cursor="pointer" direction="row" align-items="center" column-gap={16}
			height={ROW} padding="0 24" transform={fall(props.i)} motion-transform="bouncy" background={freeze() ? (night() ? "#1b2b45" : "#f1f8ff") : night() ? "#161a2b" : "#ffffff"}
			border-width="0 0 1 0" border-color={night() ? "#262b40" : "#eceef3"} onPress={() -> r.on(!r.on())}>
			<view width={40} height={40} radius={11} align-items="center" justify="center" background={r.tint}>
				<image src={icon(r.icon)} width={20} height={20} color="#ffffff"/>
			</view>
			<view grow={1} row-gap={2}>
				<text font-size={16} font-weight={600}>{r.label}</text>
				<text font-size={13} color={night() ? "#8f97b3" : "#6b7080"}>{r.detail}</text>
			</view>
			<Switch on={r.on} tint={r.tint}/>
		</view>;
	}

	// frost: crystals grown in from the edges, drawn once
	static var frostImage:Null<Image> = null;

	static function frost(w:Int, h:Int):Image {
		if (frostImage != null) return frostImage;
		var c = new Canvas(w, h), seed = 7;
		function rnd():Float {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return seed / 0x7fffffff;
		}
		var lines = new Path();
		function branch(x:Float, y:Float, a:Float, len:Float, depth:Int) {
			if (depth == 0 || len < 3) return;
			var x2 = x + Math.cos(a) * len, y2 = y + Math.sin(a) * len;
			lines.moveTo(x, y);
			lines.lineTo(x2, y2);
			var n = 2 + Std.int(rnd() * 2);
			for (k in 0...n) {
				var t = 0.3 + rnd() * 0.6, bx = x + (x2 - x) * t, by = y + (y2 - y) * t;
				branch(bx, by, a + (rnd() < 0.5 ? -1 : 1) * (0.5 + rnd() * 0.6), len * (0.35 + rnd() * 0.25), depth - 1);
			}
			branch(x2, y2, a + (rnd() - 0.5) * 0.5, len * 0.7, depth - 1);
		}
		for (k in 0...18) {
			var side = k % 4, u = rnd();
			var x = side == 0 ? 0 : side == 1 ? w : u * w, y = side == 2 ? 0 : side == 3 ? h : u * h;
			var a = side == 0 ? 0.0 : side == 1 ? Math.PI : side == 2 ? Math.PI / 2 : -Math.PI / 2;
			branch(x, y, a + (rnd() - 0.5) * 1.2, 30 + rnd() * 60, 4);
		}
		c.saveLayer(1, null, null, new Blur(2.5));
		c.stroke(lines, new Stroke(2.2), Paint.solid(0x99ffffff));
		c.restore();
		c.stroke(lines, new Stroke(0.8), Paint.solid(0xccffffff));
		var px = Bytes.alloc(w * h * 4);
		c.readPixels(px, 0, 0, w, h);
		return frostImage = new Image(w, h, px);
	}

	static function Sky():View
		return <view position="absolute" left={0} top={0} right={0} bottom={0} motion-color="calm"
			background={night() ? "linear-gradient(180deg, #070b1f 0%, #1b1a46 70%, #3a2a5c 100%)" : "linear-gradient(180deg, #7fb8ff 0%, #bfe0ff 60%, #ffe7cf 100%)"}>
			<Repeat count={46}>{i -> <view position="absolute" left={(hash(i) % 1280)} top={(hash(i + 99) % 420)} width={i % 7 == 0 ? 3 : 2}
				height={i % 7 == 0 ? 3 : 2} radius={2} background="#ffffff" opacity={night() ? 0.35 + (hash(i + 5) % 60) / 100 : 0} motion-opacity="calm"/>}</Repeat>
			<view position="absolute" left={170} top={150} width={110} height={110} radius={55} background="#ffd36e" shadow="0 0 60px rgba(255, 200, 90, 0.8)"
				transform={night() ? "translate(0px, 460px)" : "none"} motion-transform="1.4 0"/>
			<view position="absolute" left={1010} top={110} width={70} height={70} radius={35} background="#f1f0ff" shadow="0 0 40px rgba(220, 220, 255, 0.6)"
				transform={night() ? "none" : "translate(0px, 520px)"} motion-transform="1.6 0"/>
			<view position="absolute" left={-200} right={-200} bottom={-520} height={760} radius={380} background={night() ? "#141a33" : "#7fc28a"}/>
			<view position="absolute" left={520} right={-300} bottom={-560} height={760} radius={380} background={night() ? "#0d1226" : "#5aa66a"}/>
		</view>;

	static function hash(i:Int):Int {
		var h = i * 0x45d9f3b;
		h = (h ^ (h >>> 16)) * 0x45d9f3b;
		return (h ^ (h >>> 16)) & 0x7fffffff;
	}

	public static function view():View
		return <view grow={1} align-items="center" justify="center" font-family="Inter" motion={freeze() ? "2.8 0.1" : "default"}>
			{Sky()}
			<view tag="panel" z-index={1} width={560} height={PANEL_H} radius={22} overflow="hidden" dir={rtl() ? "rtl" : "ltr"}
				background={freeze() ? (night() ? "#16243cee" : "#e6f4ffee") : night() ? "#11152aee" : "#f7f8fbee"} color={night() ? "#eef1fb" : "#14161d"}
				shadow="0 30px 80px rgba(10, 20, 50, 0.35)" border-width={1} border-color={night() ? "#2a3150" : "#ffffffaa"}>
				<view height={HEAD} padding="26 24 0 24" row-gap={4}>
					<text font-size={26} font-weight={700} letter-spacing={-0.5}>Preferences</text>
					<text font-size={14} color={night() ? "#8f97b3" : "#6b7080"}>Every setting here does exactly what it says.</text>
				</view>
				<For each={() -> order()}>{(i:Read<Int>) -> <Row i={untrack(() -> i())}/>}</For>
				<image position="absolute" left={0} top={0} width={560} height={PANEL_H} src={frost(560, PANEL_H)} opacity={freeze() ? 1 : 0}
					pointer-events="none" motion-opacity="2.2 0"/>
			</view>
		</view>;

	static function main() {
		try helder.text.SystemFonts.get().add(helder.asset.Asset.embed("fonts/Inter.ttf")) catch (_:Dynamic) {}
		UiWindow.run(<Surface title="Taken literally" width={1280} height={720} background="#7fb8ff">{view()}</Surface>);
	}
}
