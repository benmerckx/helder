package helder.ui.widgets;

import helder.os.TitleBar.TitleHit;
import helder.ui.Node;
import helder.ui.SafeArea;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The window's buttons in an inset title bar (helder.os's TitleBar, a
// <Surface titlebar="inset">), where the app's layout puts them: macOS's own
// (a box of their size, the system's buttons placed at it: Ui.controlsAt),
// else drawn here: Windows' minimise, maximise and close (46 by 32, the
// close button red when hovered; the maximise button Windows' snap
// layouts' through WM_NCHITTEST), Linux's round ones. Nothing where the
// window has the system's title bar, in the browser or on a phone. Its
// colour is the text's (currentColor).
//   <view direction="row" drag-region><text>Title</text><view grow={1}/><WindowControls/></view>
// A layout whose top left and top right are different bars (a sidebar's,
// an inspector's) puts one at each end with its side: only the one where
// the system puts them is drawn (side(): macOS's at the start, Windows' and
// Linux's at the end), the other nothing.
//   <view drag-region><WindowControls side="start"/><text>Project</text></view>
//   <view drag-region><text>Inspector</text><view grow={1}/><WindowControls side="end"/></view>
class WindowButtons implements Markup {
	// the side of the window the system puts its buttons: "start" (macOS's,
	// at the left: env(titlebar-area-x) after them), "end" (Windows', Linux's),
	// null without an inset title bar (the system's, the browser, a phone).
	// Reactive, as SafeArea.titlebar: a bar's padding at that end can follow it.
	public static function side():Null<String> {
		var t = SafeArea.titlebar();
		return t == null ? null : t.x > 0 ? "start" : "end";
	}

	public static function WindowControls(props:{?tag:String, ?side:String}):View {
		if (props.side != null) {
			var at = props.side;
			return <Show when={side() == at}>{controls(props.tag)}</Show>;
		}
		return controls(props.tag);
	}

	static function controls(tag:Null<String>):View {
		tag = tag ?? "window-controls";
		var kind = signal("none"), size = signal({w: 0.0, h: 0.0}), node:Null<Node> = null;
		onCleanup(() -> if (node != null && node.ui != null && node.ui.controlsAt == node) node.ui.controlsAt = null);
		// (its window known once it is laid out in one: its first onResize)
		return <view tag={tag} direction="row" align-items="center" shrink={0} width={kind() == "system" ? size().w : kind() == "none" ? 0.0 : (null : Null<Float>)}
			height={kind() == "system" ? size().h : kind() == "none" ? 0.0 : (null : Null<Float>)} ref={(n:Node) -> node = n} onResize={e -> {
				var n = node;
				if (n == null || n.ui == null || kind.peek() != "none") return;
				var w = n.ui.window;
				var k = w == null ? "none" : w.controls();
				if (k == "none") return;
				if (k == "system") {
					var b = w.systemControls();
					if (b != null) size({w: b.width, h: b.height});
					n.ui.controlsAt = n;
				}
				kind(k);
			}}>
			{kind() == "system" ? standIns() : kind() == "none" ? null : buttons(kind() == "linux")}
		</view>;
	}

	// (a headless run of a macOS build: no system's buttons drawn, circles where they are)
	static function standIns():View {
		#if helder.headless
		return <view direction="row" column-gap={8} padding="2 1">
			{[for (_ in 0...3) <view width={12} height={12} radius={6} background="#ffffff" opacity={0.16}/>]}
		</view>;
		#else
		return null;
		#end
	}

	static function buttons(linux:Bool):View {
		var w = helder.os.TitleBar.TitleBars.button(linux), h = helder.os.TitleBar.TitleBars.HEIGHT;
		return <view direction="row" height={h}>
			{button("window-minimize", "Minimize", Minimize, w, h, linux, n -> n.ui.window.minimize(), <image src={minimize()} width={10} height={10}/>)}
			{button("window-maximize", "Maximize", Maximize, w, h, linux, n -> n.ui.window.maximize(!n.ui.window.maximized()),
				<image src={maximize(linux)} width={10} height={10}/>)}
			{button("window-close", "Close", Close, w, h, linux, n -> n.ui.window.close(), <image src={close()} width={10} height={10}/>)}
		</view>;
	}

	// (the glyphs as SVGs: their currentColor the text's, as an image's;
	// a view's own background="currentColor" is not resolved)
	static var minimizeSvg:Null<helder.ui.Svg> = null;
	static var maximizeSvgs:Array<Null<helder.ui.Svg>> = [null, null];

	static function minimize():helder.ui.Svg {
		if (minimizeSvg == null)
			minimizeSvg = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" fill="none" stroke="currentColor" stroke-width="1"><path d="M0 5.5h10"/></svg>');
		return minimizeSvg;
	}

	static var closeSvg:Null<helder.ui.Svg> = null;

	// (Windows' own: corner to corner of the 10 by 10 square, as wide as the others)
	static function close():helder.ui.Svg {
		if (closeSvg == null)
			closeSvg = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" fill="none" stroke="currentColor" stroke-width="1"><path d="M0.5 0.5l9 9M9.5 0.5l-9 9"/></svg>');
		return closeSvg;
	}

	static function maximize(linux:Bool):helder.ui.Svg {
		var i = linux ? 1 : 0;
		if (maximizeSvgs[i] == null)
			maximizeSvgs[i] = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" fill="none" stroke="currentColor" stroke-width="1"><rect x="0.5" y="0.5" width="9" height="9" rx="${linux ? 1 : 0}"/></svg>');
		return maximizeSvgs[i];
	}

	static function button(tag:String, label:String, hit:TitleHit, w:Int, h:Int, linux:Bool, press:Node->Void, glyph:View):View {
		var over = signal(false), node:Null<Node> = null;
		var close = hit == Close;
		return <view tag={tag} role="button" label={label} width={w} height={h} align-items="center" justify="center"
			ref={(n:Node) -> {
				node = n;
				n.titleHit = hit;
			}} onPointerEnter={() -> over(true)} onPointerLeave={() -> over(false)} onPress={() -> if (node != null && node.ui != null && node.ui.window != null) press(node)}
			color={close && over() && !linux ? "#ffffff" : null}>
			<view width={linux ? 24 : w} height={linux ? 24 : h} radius={linux ? 12 : 0} align-items="center" justify="center"
				background={over() ? (close && !linux ? "#c42b1c" : "rgba(127,127,127,0.18)") : linux ? "rgba(127,127,127,0.1)" : "transparent"}>{glyph}</view>
		</view>;
	}
}
