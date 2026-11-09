package helder.ui.widgets;

import helder.os.TitleBar.TitleHit;
import helder.ui.Node;
import helder.view.*;
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
class WindowButtons implements Markup {
	public static function WindowControls(props:{?tag:String}):View {
		var tag = props.tag ?? "window-controls";
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
			{button("window-minimize", "Minimize", Minimize, w, h, linux, n -> n.ui.window.minimize(), <view width={10} height={1} background="currentColor"/>)}
			{button("window-maximize", "Maximize", Maximize, w, h, linux, n -> n.ui.window.maximize(!n.ui.window.maximized()),
				<view width={9} height={9} border-width={1} border-color="currentColor" radius={linux ? 1 : 0}/>)}
			{button("window-close", "Close", Close, w, h, linux, n -> n.ui.window.close(), <icon name="x" width={12} height={12}/>)}
		</view>;
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
