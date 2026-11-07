package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Theme.c;

using StringTools;

// The canvas: every screen of the project at once, grouped by flow (a row
// each), their frames the programs' (Previews: refreshed as they draw).
// Pan with a drag or the wheel, zoom with secondary and the wheel (a
// trackpad's pinch) or two fingers; a screen clicked zooms into it on a
// spring, a click inside the zoomed screen selects the node there (the
// program's tree, the node's source), drawn as a cyan box with handles.
// The world (the screens) is one node under the camera's transform; what is
// read at any zoom (flows' titles, captions, the selection) is drawn in the
// stage's own points from the camera.
class Board implements Markup {
	public static function view(studio:Studio):View {
		var stage:Null<Node> = null;
		return <view tag="stage" grow={1} min-width={0} overflow="hidden" cursor="default" ref={n -> {
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
			onPinch={g -> studio.camera.zoomAt(g.x, g.y, g.dscale)}>
			<Show when={studio.mode() != "stories"}>
				<view tag="world" position="absolute" left={0} top={0} width={1} height={1} transform-origin="left top" transform={transform(studio)}>
					<For each={studio.layout.screens()}>{(r:Read<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}>) -> {
						var s = studio.previews.screen(r().name);
						<view tag={"screen-" + Shell.slug(s.info.name)} slot="screen" position="absolute" left={r().x} top={r().y} width={r().w}
							height={r().h} data-on={studio.focused() == s.info.name ? "true" : "false"} data-frame={s.frames()}>
							<image src={s.image()} width={r().w} height={r().h}/>
							<Show when={s.frames() == 0}>
								<view position="absolute" inset={0} align-items="center" justify="center">
									<text color={c("fg3")} font-size={12}>{studio.previews.failed ? "the build failed" : "building…"}</text>
								</view>
							</Show>
						</view>;
					}}</For>
				</view>
				{overlay(studio)}
			</Show>
			<Show when={studio.mode() == "stories"}>{stories(studio)}</Show>
			<Show when={studio.focused() != null && studio.mode() == "design"}>{Inspector.view(studio)}</Show>
			<Show when={studio.mode() != "code"}>{Prompt.view(studio)}</Show>
		</view>;
	}

	static function transform(studio:Studio):String {
		studio.camera.changed();
		return studio.camera.transform();
	}

	// what is drawn in the stage's points: the flows' titles and lines, the screens' captions, the selection
	static function overlay(studio:Studio):View {
		return <view tag="overlay" position="absolute" inset={0} pointer-events="none">
			<For each={flows(studio)}>{(f:Read<{name:String, x:Float, y:Float}>) ->
				<text tag="flow-title" position="absolute" left={sx(studio, f().x)} top={sy(studio, f().y) - 48} font-size={12} font-weight={Theme.MEDIUM}
					color={c("fg2")}>{f().name}</text>
			}</For>
			<For each={links(studio)}>{(l:Read<{x:Float, y:Float, w:Float}>) ->
				<view position="absolute" left={sx(studio, l().x)} top={sy(studio, l().y)} width={l().w * k(studio)} height={1} background={c("sel-soft")}/>
			}</For>
			<For each={studio.layout.screens()}>{(r:Read<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}>) ->
				<view tag="caption" position="absolute" left={sx(studio, r().x)} top={sy(studio, r().y) - 22} direction="row" align-items="center" column-gap={6}>
					<view width={6} height={6} radius={3} background={c("k-screen")}/>
					<text font-size={Theme.LABEL} color={studio.focused() == r().name ? c("fg2") : c("fg3")}>{label(studio, r().name)}</text>
				</view>
			}</For>
			<Show when={selected(studio) != null}>{selectionBox(studio)}</Show>
		</view>;
	}

	// the selected node's box (the zoomed screen's), its four handles
	static function selectionBox(studio:Studio):View {
		function box():{x:Float, y:Float, w:Float, h:Float} {
			var s = selected(studio), r = s == null ? null : studio.layout.rect(s.screen);
			if (s == null || r == null) return {x: -100, y: -100, w: 0, h: 0};
			studio.camera.changed();
			var kk = studio.camera.k;
			return {x: studio.camera.sx(r.x + s.x), y: studio.camera.sy(r.y + s.y), w: s.width * kk, h: s.height * kk};
		}
		return <view tag="selection" position="absolute" left={box().x} top={box().y} width={box().w} height={box().h} border-width={1.2}
			border-color={c("sel")}>
			<view slot="handle" position="absolute" left={-3.5} top={-3.5} width={6} height={6} radius={1} background={c("panel")} border-width={1.2} border-color={c("sel")}/>
			<view slot="handle" position="absolute" right={-3.5} top={-3.5} width={6} height={6} radius={1} background={c("panel")} border-width={1.2} border-color={c("sel")}/>
			<view slot="handle" position="absolute" left={-3.5} bottom={-3.5} width={6} height={6} radius={1} background={c("panel")} border-width={1.2} border-color={c("sel")}/>
			<view slot="handle" position="absolute" right={-3.5} bottom={-3.5} width={6} height={6} radius={1} background={c("panel")} border-width={1.2} border-color={c("sel")}/>
		</view>;
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
				<view:button tag={"story-" + Shell.slug(i.name)} slot="nav-item" role="button" label={i.name} focusable onPress={() -> {
					studio.setMode("design");
					studio.focus(i.name);
				}}>
					<view slot="badge"><text>S</text></view>
					<text grow={1}>{i.name}</text>
					<text font-family={Theme.CODE} font-size={Theme.VALUE} color={c("fg3")}>{(i.width > 0 ? i.width + " × " + i.height + "  " : "")
						+ Shell.fileLabel(studio, i.file)}</text>
				</view:button>;
			}}</For>
		</scroll>;
	}

	static function flows(studio:Studio):Array<{name:String, x:Float, y:Float}> {
		var out:Array<{name:String, x:Float, y:Float}> = [];
		for (r in studio.layout.screens())
			if (!Lambda.exists(out, f -> f.name == r.flow)) out.push({name: r.flow, x: r.x, y: r.y});
		return out;
	}

	// (a line between screens of a flow, at their middle)
	static function links(studio:Studio):Array<{x:Float, y:Float, w:Float}> {
		var l = studio.layout.screens(), out:Array<{x:Float, y:Float, w:Float}> = [];
		for (i in 0...l.length - 1)
			if (l[i].flow == l[i + 1].flow) out.push({x: l[i].x + l[i].w, y: l[i].y + Math.min(l[i].h, l[i + 1].h) / 2, w: Theme.SCREEN_GAP + 0.0});
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

	static function k(studio:Studio):Float {
		studio.camera.changed();
		return studio.camera.k;
	}
}
