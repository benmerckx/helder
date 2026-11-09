package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;
import studio.Theme.c;

using StringTools;

// Play (the toolbar's): what is selected run as it would run, else the app
// from its start. In the studio (the default target; the only one in the
// browser): a story full size and live, the pointer's, the wheel's and the
// keys' events its own (the preview host's Input.*), its controls in a panel
// (Story.controls, Story.set); the app the same (a project whose program is
// its stories has no App screen: run it in a window instead); a design's
// frame as a prototype, the page's frames one after the other with the
// arrow keys (flows and interactions are not made yet). Elsewhere a target
// is `helder dev` on the project (StudioCommand's helder, HELDER_CLI): a
// window of its own (hot reload kept), a phone (Android's, connected:
// --target android), a browser's tab (--target web, the page it serves
// opened). Escape or Stop ends it.
class Play implements Markup {
	public static final targets = ["studio", "window", "phone", "browser"];

	public static function label(t:String):String
		return switch t {
			case "window": "Window";
			case "phone": "Phone";
			case "browser": "Browser";
			case _: "Studio";
		}

	public static function icon(t:String):Svg
		return switch t {
			case "window": Icons.appWindow;
			case "phone": Icons.smartphone;
			case "browser": Icons.globe;
			case _: Icons.monitor;
		}

	// the toolbar's Play and the target beside it
	public static function button(studio:Studio):View {
		var picking = signal(false);
		return <view direction="row" align-items="center" column-gap={2}>
			<view:button tag="play" slot="primary" role="button" label={studio.playing() == null ? "Play" : "Stop"} focusable
				onPress={() -> if (studio.playing.peek() != null) studio.stopPlay() else studio.play()}>
				<image src={studio.playing() == null ? Icons.play : Icons.element} width={Theme.ICON_S} height={Theme.ICON_S}/>
				<text>{studio.playing() == null ? "Play" : "Stop"}</text>
			</view:button>
			<Show when={targetsHere().length > 1}>
				<view:button tag="play-target" slot="button" role="button" label={"Play in: " + label(studio.target())} focusable data-on={picking() ? "true" : "false"}
					onPress={() -> picking(!picking.peek())}>
					<image src={icon(studio.target())} width={Theme.ICON_S} height={Theme.ICON_S}/>
					<image src={Icons.chevronDown} width={12} height={12}/>
				</view:button>
			</Show>
			<Show when={picking()}>
				<view tag="play-targets" slot="floating" position="absolute" top={Theme.HEADER} right={0} width={210} padding={6} shadow="0 12 32 rgba(0,0,0,0.45)"
					transition="fade" motion="snappy">
					{[for (t in targetsHere()) <view:button tag={"target-" + t} slot="menu-item" role="button" label={label(t)} data-on={studio.target() == t ? "true" : "false"}
						onPress={() -> {
							studio.target(t);
							picking(false);
						}}>
						<image src={icon(t)} width={Theme.ICON_S} height={Theme.ICON_S}/>
						<text grow={1}>{label(t)}</text>
						<text font-size={Theme.SMALL} color={c("fg3")}>{t == "studio" ? "here" : t == "phone" ? "Android" : "helder dev"}</text>
					</view:button>]}
				</view>
			</Show>
		</view>;
	}

	// (in the browser the studio's own alone)
	static function targetsHere():Array<String>
		return #if (hxmc.target == "wasm32-wasi") ["studio"] #else targets #end;

	// the player over the canvas
	public static function view(studio:Studio):View {
		var p = studio.playing();
		if (p == null) return null;
		var info = p.screen == null ? null : studio.project.screen(p.screen);
		return <view tag="player" grow={1} min-height={0} background={c("canvas")} onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<view tag="player-head" direction="row" align-items="center" column-gap={10} height={44} padding="0 10 0 14" background={c("bg")}
				border-width="0 0 1 0" border-color={c("line")} shrink={0}>
				<image src={p.kind == "design" ? Icons.penTool : p.kind == "app" ? Icons.appWindow : p.kind == "target" ? icon(studio.target()) : Icons.bookOpen}
					width={Theme.ICON} height={Theme.ICON} color={c("accent")}/>
				<text font-weight={Theme.MEDIUM} max-lines={1}>{info == null ? label(studio.target()) : info.label}</text>
				<text tag="player-note" font-size={Theme.SMALL} color={c("fg3")} max-lines={1} shrink={1}>{p.kind == "target" ? studio.playLog() : p.note}</text>
				<view grow={1}/>
				<Show when={p.kind == "design"}>
					<view:button tag="player-prev" slot="button" role="button" label="The frame before" onPress={() -> studio.playStep(-1)}>
						<image src={Icons.chevronRight} width={Theme.ICON_S} height={Theme.ICON_S} transform="rotate(180deg)"/>
					</view:button>
					<view:button tag="player-next" slot="button" role="button" label="The next frame" onPress={() -> studio.playStep(1)}>
						<image src={Icons.chevronRight} width={Theme.ICON_S} height={Theme.ICON_S}/>
					</view:button>
				</Show>
			</view>
			<view direction="row" grow={1} min-height={0}>
				<view tag="player-stage" grow={1} min-width={0} align-items="center" justify="center" focusable ref={(n:Node) -> haxe.Timer.delay(() -> n.focus(false), 0)}
					onKeyDown={e -> key(studio, p, e, "down")} onKeyUp={e -> key(studio, p, e, "up")} onTextInput={e -> if (p.kind != "design") send(studio, p, "Input.text", {text: e.text})}>
					{p.kind == "target" ? <text color={c("fg3")} padding={24}>{"Running in " + label(studio.target()).toLowerCase() + ": its output above."}</text>
						: info == null ? <text color={c("fg3")} padding={24}>{p.note}</text>
						: p.kind == "design" ? design(studio, info) : live(studio, p, info)}
				</view>
				<Show when={p.kind == "story"}>{controls(studio, p)}</Show>
			</view>
		</view>;
	}

	// (the frame's scale: 1:1, else fitted into the player)
	static function fit(studio:Studio, w:Float, h:Float, panel:Bool):Float {
		studio.stageSize();
		var aw = studio.stageWidth - (studio.compact() ? 0 : Theme.SIDEBAR + 3 * Theme.GAP) - (panel ? Theme.INSPECTOR : 0) - 48;
		var ah = studio.stageHeight - (studio.compact() ? 0 : Theme.HEADER + 2 * Theme.GAP) - 44 - 48;
		return Math.min(1, Math.min(aw / Math.max(1, w), ah / Math.max(1, h)));
	}

	// a story's or the app's screen: its frames, its input the program's
	static function live(studio:Studio, p:Playing, info:Project.ScreenInfo):View {
		var s = studio.previews?.screen(info.name);
		if (s == null) return <text color={c("fg3")}>{"Not built yet."}</text>;
		var down = false;
		function at(e:Event):{x:Float, y:Float} {
			var k = fit(studio, s.width(), s.height(), p.kind == "story");
			return {x: e.localX / k, y: e.localY / k};
		}
		return <view tag="player-screen" width={s.width() * fit(studio, s.width(), s.height(), p.kind == "story")}
			height={s.height() * fit(studio, s.width(), s.height(), p.kind == "story")} radius={2} overflow="hidden" shadow="0 16 48 rgba(0,0,0,0.45)"
			onPointerDown={e -> {
				down = true;
				var q = at(e);
				send(studio, p, "Input.pointer", {type: "down", x: q.x, y: q.y, button: 1});
			}} onPointerMove={e -> {
				var q = at(e);
				send(studio, p, "Input.pointer", {type: "move", x: q.x, y: q.y});
			}} onPointerUp={e -> {
				down = false;
				var q = at(e);
				send(studio, p, "Input.pointer", {type: "up", x: q.x, y: q.y, button: 1});
			}} onWheel={e -> {
				var q = at(e);
				send(studio, p, "Input.wheel", {x: q.x, y: q.y, dx: e.deltaX, dy: e.deltaY});
				e.stop();
			}}>
			<image src={s.image()} width="100%" height="100%"/>
		</view>;
	}

	// a design's frame at its size (fitted), its nodes as the canvas draws them
	static function design(studio:Studio, info:Project.ScreenInfo):View {
		var w = info.width > 0 ? info.width : 390, h = info.height > 0 ? info.height : 844, k = fit(studio, w, h, false);
		return <view tag="player-design" width={w * k} height={h * k} radius={2} overflow="hidden" shadow="0 16 48 rgba(0,0,0,0.45)">
			<view width={w} height={h} transform-origin="left top" transform={'scale($k)'} pointer-events="none" background="#ffffff" color="#000000"
				font-family={helder.ui.Style.DEFAULT_FAMILY} font-size={helder.ui.Style.DEFAULT_SIZE} font-weight={helder.ui.Style.DEFAULT_WEIGHT}
				ref={(n:Node) -> n.theme = {rules: []}}>{studio.designs.content(info.name)}</view>
		</view>;
	}

	// a story's controls: each kind its field, set in the program at once
	static function controls(studio:Studio, p:Playing):View {
		return <view tag="player-controls" width={Theme.INSPECTOR} shrink={0} background={c("bg")} border-width="0 0 0 1" border-color={c("line")}>
			<view slot="section" border-width={0}>
				<view slot="section-head"><image src={Icons.ruler} width={12} height={12}/><text>Controls</text></view>
				<Show when={studio.playControls().length > 0} fallback={<text font-size={Theme.SMALL} color={c("fg3")}>{"This story has no controls."}</text>}>
					<For each={studio.playControls()} by={(x:Dynamic) -> x.name}>{(x:Read<Dynamic>) -> {
						var ctl:Dynamic = x();
						<view tag={"control-" + Shell.slug(ctl.name)} slot="field">
							<text slot="field-label" cursor="default" max-lines={1}>{ctl.name}</text>
							{switch (ctl.kind : String) {
								case "bool": <view:button slot="seg-item" role="button" label={ctl.name} data-on={ctl.value == true ? "true" : "false"}
										onPress={() -> studio.setControl(ctl.name, ctl.value != true)}><text>{ctl.value == true ? "On" : "Off"}</text></view:button>;
								case "choice": <view slot="seg">{[for (o in (ctl.options : Array<String>)) <view:button slot="seg-item" role="button" label={o}
										data-on={ctl.value == o ? "true" : "false"} onPress={() -> studio.setControl(ctl.name, o)}><text>{o}</text></view:button>]}</view>;
								case kind: <field slot="field-input" label={ctl.name} value={kind == "color" ? "#" + StringTools.hex(ctl.value, 8) : Std.string(ctl.value)}
										onInput={e -> studio.setControl(ctl.name, kind == "number" ? Std.parseFloat(e.text) : kind == "color" ? Std.parseInt("0x" + e.text.replace("#", "")) : e.text)}/>;
							}}
						</view>;
					}}</For>
				</Show>
			</view>
		</view>;
	}

	static function key(studio:Studio, p:Playing, e:Event, type:String) {
		if (e.key == Key.ESCAPE) {
			if (type == "down") studio.stopPlay();
			e.stop();
			return;
		}
		if (p.kind == "design") {
			if (type == "down" && (e.key == Key.RIGHT || e.key == Key.DOWN)) studio.playStep(1);
			if (type == "down" && (e.key == Key.LEFT || e.key == Key.UP)) studio.playStep(-1);
			return;
		}
		send(studio, p, "Input.key", {type: type, key: e.key, mods: e.mods});
		e.stop();
	}

	static function send(studio:Studio, p:Playing, method:String, params:Dynamic) {
		var s = p.screen == null ? null : studio.previews?.screen(p.screen);
		if (s != null) studio.previews.request(s, method, params, _ -> {});
	}
}

// what plays: its kind ("story", "app", "design"; "target": another target's
// process), its screen, what to say about it
typedef Playing = {kind:String, screen:Null<String>, note:String};
