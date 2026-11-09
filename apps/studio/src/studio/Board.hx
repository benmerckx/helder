package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Project.Source;
import studio.Theme.c;

using StringTools;

// The canvas: every screen of the project at once, grouped by flow (a row
// each), a story's frames the program's (Previews: refreshed as they draw),
// a design's frame its own nodes, interpreted here (Designs).
// Pan with a drag or the wheel, zoom with secondary and the wheel (a
// trackpad's pinch) or two fingers; a screen clicked zooms into it on a
// spring, a click inside the zoomed screen selects the node there (the
// program's tree, the node's source), outlined.
// The world (the screens) is one node under the camera's transform; what is
// read at any zoom (flows' titles, captions, the selection) is drawn in the
// stage's own points from the camera.
class Board implements Markup {
	public static function view(studio:Studio):View {
		var stage:Null<Node> = null;
		return <view tag="stage" grow={1} min-width={0} overflow="hidden" cursor="default" background={c("canvas")} ref={n -> {
			stage = n;
			studio.stageNode = n;
		}}
			onClick={e -> if (studio.mode() != "stories") studio.clickStage(e.localX, e.localY)}
			onWheel={e -> {
				if (e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0) studio.camera.zoomAt(e.localX, e.localY, Math.exp(-e.deltaY * 0.0025))
				else studio.camera.panBy(-e.deltaX, -e.deltaY);
				e.preventDefault();
				e.stop();
			}}
			onPan={g -> studio.camera.panBy(g.dx, g.dy)}
			onPinch={g -> {
				studio.camera.zoomAt(g.x, g.y, g.dscale);
				if (g.state == Ended) studio.log("pinched", {k: studio.camera.k});
			}}>
			<Show when={studio.mode() != "stories"}>
				<view tag="world" position="absolute" left={0} top={0} width={1} height={1} transform-origin="left top" transform={transform(studio)}>
					<For each={studio.layout.screens()}>{(r:Read<Rect>) -> {
						var info = studio.project.screen(r().name);
						info.source.match(Design(_)) ? design(studio, r, info) : live(studio, r);
					}}</For>
				</view>
				{overlay(studio)}
			</Show>
			<Show when={studio.mode() == "stories"}>{stories(studio)}</Show>
			<Show when={studio.focused() != null && studio.mode() == "design" && !studio.drawer()}>{Inspector.view(studio)}</Show>
			<Show when={studio.mode() != "code" && !(studio.compact() && studio.focused() != null)}>{Prompt.view(studio)}</Show>
		</view>;
	}

	// a story's or the app's screen: the program's last frame
	static function live(studio:Studio, r:Read<Rect>):View {
		var s = studio.previews.screen(r().name);
		return <view tag={"screen-" + Shell.slug(s.info.name)} slot="screen" position="absolute" left={r().x} top={r().y} width={r().w}
			height={r().h} data-on={studio.focused() == s.info.name ? "true" : "false"} data-frame={s.frames()}>
			<image src={s.image()} width={r().w} height={r().h}/>
			<Show when={s.crashedSignal()}>
				<text tag="crashed" position="absolute" left={8} top={8} color={c("fg2")} font-size={Theme.SMALL}>stopped</text>
			</Show>
			<Show when={s.frames() == 0 && !s.crashedSignal()}>
				<view position="absolute" inset={0} align-items="center" justify="center">
					<text color={c("fg3")} font-size={Theme.SMALL}>{studio.previews.failed ? "the build failed" : "building…"}</text>
				</view>
			</Show>
		</view>;
	}

	// a design's frame: its nodes, interpreted, under a theme of none and
	// ui's own defaults (not the studio's), as the app would draw them; a
	// click goes through them to the stage
	static function design(studio:Studio, r:Read<Rect>, info:Project.ScreenInfo):View
		return <view tag={"screen-" + Shell.slug(info.name)} slot="screen" position="absolute" left={r().x} top={r().y} width={r().w}
			height={r().h} data-on={studio.focused() == info.name ? "true" : "false"}>
			<view tag="design" width={r().w} height={r().h} overflow="hidden" pointer-events="none" background="#ffffff" color="#000000"
				font-family={helder.ui.Style.DEFAULT_FAMILY} font-size={helder.ui.Style.DEFAULT_SIZE} font-weight={helder.ui.Style.DEFAULT_WEIGHT}
				ref={(n:Node) -> n.theme = {rules: []}}>
				{studio.designs.content(info)}
			</view>
		</view>;

	static function transform(studio:Studio):String {
		studio.camera.changed();
		return studio.camera.transform();
	}

	// what is drawn in the stage's points: the flows' titles and lines, the screens' captions, the selection
	static function overlay(studio:Studio):View {
		return <view tag="overlay" position="absolute" inset={0} pointer-events="none">
			<For each={flows(studio)}>{(f:Read<{name:String, x:Float, y:Float}>) ->
				<text tag="flow-title" position="absolute" left={sx(studio, f().x)} top={sy(studio, f().y) - 46} font-size={Theme.SMALL}
					color={c("fg2")} opacity={titleShown(studio, f().y) ? 1 : 0}>{f().name}</text>
			}</For>
			<For each={studio.layout.screens()}>{(r:Read<Rect>) ->
				<text tag="caption" position="absolute" left={sx(studio, r().x)} top={sy(studio, r().y) - 20} font-size={Theme.SMALL}
					color={studio.focused() == r().name ? c("fg2") : c("fg3")}>{label(studio, r().name)}</text>
			}</For>
			<Show when={selected(studio) != null}>{selectionBox(studio)}</Show>
		</view>;
	}

	// the selected node's box (the zoomed screen's), outlined
	static function selectionBox(studio:Studio):View {
		function box():{x:Float, y:Float, w:Float, h:Float} {
			var s = selected(studio), r = s == null ? null : studio.layout.rect(s.screen);
			if (s == null || r == null) return {x: -100, y: -100, w: 0, h: 0};
			studio.camera.changed();
			var kk = studio.camera.k;
			return {x: studio.camera.sx(r.x + s.x), y: studio.camera.sy(r.y + s.y), w: s.width * kk, h: s.height * kk};
		}
		// (a node selected: the box springs to it, helder.ui.motion; the camera moving it: with the camera, at once)
		var camAt = -1, was:Null<Studio.Selection> = null;
		function still():Bool {
			var s = selected(studio), cc = studio.camera.changed();
			if (s != was) {
				was = s;
				camAt = cc;
			}
			return cc != camAt;
		}
		return <view tag="selection" position="absolute" left={box().x} top={box().y} width={box().w} height={box().h} border-width={1}
			border-color={c("sel")} outline-width={1} outline-color={c("sel-halo")} motion="snappy" instant={still()}/>;
	}

	// (the selection while its screen is the one zoomed into)
	static function selected(studio:Studio):Null<Studio.Selection> {
		var s = studio.selection();
		return s != null && studio.focused() == s.screen ? s : null;
	}

	static function stories(studio:Studio):View {
		var p = studio.project;
		return <scroll tag="stories" position="absolute" inset={0} padding="20 24" row-gap={6}>
			<For each={p == null ? [] : p.screens}>{(s:Read<Project.ScreenInfo>) -> {
				var i = s();
				<view:button tag={"story-" + Shell.slug(i.name)} slot="nav-item" column-gap={12} role="button" label={i.name} focusable onPress={() -> {
					studio.setMode("design");
					studio.focus(i.name);
				}}>
					<text grow={1}>{i.name}</text>
					<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg3")}>{(i.width > 0 ? i.width + " × " + i.height + "  " : "")
						+ Shell.fileLabel(studio, i.file)}</text>
				</view:button>;
			}}</For>
		</scroll>;
	}

	// (a flow's title above its row: the first's always, the others' while the rows are far enough apart to hold it, not over the row before)
	static function titleShown(studio:Studio, wy:Float):Bool {
		studio.camera.changed();
		return wy <= 0 || Theme.FLOW_GAP * studio.camera.k >= 50;
	}

	static function flows(studio:Studio):Array<{name:String, x:Float, y:Float}> {
		var out:Array<{name:String, x:Float, y:Float}> = [];
		for (r in studio.layout.screens())
			if (!Lambda.exists(out, f -> f.name == r.flow)) out.push({name: r.flow, x: r.x, y: r.y});
		return out;
	}

	static function label(studio:Studio, name:String):String {
		var s = studio.project == null ? null : Lambda.find(studio.project.screens, x -> x.name == name);
		return s == null ? name : s.label;
	}

	static function sx(studio:Studio, wx:Float):Float {
		studio.camera.changed();
		return studio.camera.sx(wx);
	}

	static function sy(studio:Studio, wy:Float):Float {
		studio.camera.changed();
		return studio.camera.sy(wy);
	}
}

private typedef Rect = {name:String, flow:String, x:Float, y:Float, w:Float, h:Float};
