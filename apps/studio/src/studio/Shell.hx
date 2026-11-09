package studio;

import helder.ui.*;
import helder.ui.gesture.Gesture;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.ui.view.UiFlow.VirtualList;
import studio.Theme.c;

using StringTools;

// The studio's window (Theme's look): the sidebar (all screens, the
// stories, the screens by flow), the header (where you are, Design and
// Code, undo and redo), the stage: the canvas of every screen (Canvas: pan
// and zoom, a screen clicked zoomed into, a node clicked in it selected),
// the inspector floating over it while a screen is zoomed into, the prompt
// bar under it; in Code the code view beside the zoomed screen.
class Shell implements Markup {
	public static function view(studio:Studio):View {
		var p = studio.project;
		#if (hxmc.target == "wasm32-wasi")
		// (the browser without a project: the folder, the examples, OPFS's projects)
		if (p == null) return Welcome.view(studio);
		#end
		return <view tag="studio" grow={1} direction="row" ref={(n:Node) -> n.theme = Theme.sheet} background={c("bg")} color={c("fg")} font-family={Theme.UI} font-size={Theme.BODY}
			actions={[helder.ui.actions.Actions.handle(StudioAction, a -> {
				switch a {
					case Undo: studio.undo();
					case Redo: studio.redo();
					case Overview: studio.focus(null);
				}
				true;
			})]}>
			<Show when={!studio.compact()}>
				{sidebar(studio)}
				<view tag="hairline" width={1} background={c("line")}/>
			</Show>
			<view tag="main" grow={1} min-width={0}>
				{header(studio)}
				<view tag="workspace" grow={1} direction="row" min-height={0}>
					<Show when={studio.mode() == "code"}>
						<view tag="code" width={studio.compact() ? "100%" : "56%"} min-width={0} border-width="0 1 0 0" border-color={c("line")}>
							<view tag="code-head" direction="row" align-items="center" column-gap={8} height={32} padding="0 12" border-width="0 0 1 0"
								border-color={c("line")} font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg2")}>
								<text tag="code-file">{fileLabel(studio, studio.codeFile())}</text>
								<view grow={1}/>
								<text tag="code-diagnostics">{diagnosticsLabel(studio)}</text>
							</view>
							{studio.editor}
						</view>
					</Show>
					<Show when={!(studio.compact() && studio.mode() == "code")}>{Board.view(studio)}</Show>
				</view>
			</view>
			<Show when={studio.compact() && studio.drawer()}>{drawer(studio)}</Show>
		</view>;
	}

	// compact: the screens' list over the canvas, from the left, a scrim behind it (a tap there closes it)
	static function drawer(studio:Studio):View
		return <view tag="drawer-layer" position="absolute" inset={0}>
			<view tag="drawer-scrim" position="absolute" inset={0} background={c("scrim")} onClick={_ -> studio.drawer(false)}/>
			<view tag="drawer" slot="drawer" border-width="0 1 0 0" position="absolute" left={0} top={0} bottom={0} width={Theme.DRAWER} transition="slide-right(260)" motion="snappy"
				onClick={e -> e.stop()}>{sidebar(studio)}</view>
		</view>;

	static function sidebar(studio:Studio):View {
		var p = studio.project;
		return <view tag="sidebar" width={studio.compact() ? Theme.DRAWER : Theme.SIDEBAR} shrink={0} padding="10 10" row-gap={1} min-height={0} grow={studio.compact() ? 1 : 0}>
			{nav(studio, "nav-all", "All screens", () -> studio.mode() == "design" && studio.focused() == null, () -> {
				studio.drawer(false);
				studio.setMode("design");
				studio.focus(null);
			})}
			{nav(studio, "nav-stories", "Stories", () -> studio.mode() == "stories", () -> {
				studio.drawer(false);
				studio.setMode("stories");
			})}
			<VirtualList tag="screens" each={sidebarRows(p)} by={(r:SidebarRow) -> r.key} estimate={26} label="Screens">{(r:Read<SidebarRow>, i:Int) -> {
				// (a row each: a flow's name, a screen; 1 pixel between them)
				var row = r(), info = row.screen;
				<view padding="0 0 1">{info == null ? <text tag={"page-" + slug(row.flow)} padding="14 8 4" color={c("fg3")} font-size={Theme.SMALL} onClick={_ -> {
					studio.drawer(false);
					studio.showPage(row.flow);
				}}>{row.flow}</text> :
					<view:button tag={"nav-screen-" + slug(info.name)} slot="nav-item" role="button" label={info.name} focusable
						data-on={studio.focused() == info.name ? "true" : "false"} onPress={() -> {
							studio.drawer(false);
							if (studio.mode() == "stories") studio.setMode("design");
							studio.focus(info.name);
						}}>
						<text max-lines={1} text-overflow="ellipsis">{info.label}</text>
					</view:button>}</view>;
			}}</VirtualList>
		</view>;
	}

	// the sidebar's rows: each page's name (a design file, a story flow,
	// the App; a click shows its screens), then its screens (a project of
	// thousands of screens makes the rows in view only: a VirtualList)
	static function sidebarRows(p:Null<Project>):Array<SidebarRow> {
		var out:Array<SidebarRow> = [];
		if (p != null)
			for (f in p.flows()) {
				out.push({key: "flow:" + f.name, flow: f.name, screen: null});
				for (s in f.screens)
					out.push({key: "screen:" + s.name, flow: f.name, screen: s});
			}
		return out;
	}

	static function nav(studio:Studio, tag:String, label:String, on:Void->Bool, press:Void->Void):View
		return <view:button tag={tag} slot="nav-item" role="button" label={label} focusable data-on={on() ? "true" : "false"} onPress={() -> press()}>
			<text>{label}</text>
		</view:button>;

	static function header(studio:Studio):View {
		var p = studio.project;
		return <view tag="header" direction="row" align-items="center" column-gap={studio.compact() ? 6 : 16} height={Theme.HEADER}
			padding={studio.compact() ? "0 8" : "0 12 0 16"} border-width="0 0 1 0" border-color={c("line")}>
			<Show when={studio.compact()}>
				<view:button tag="menu" slot="button" role="button" label="Screens" focusable data-on={studio.drawer() ? "true" : "false"}
					onPress={() -> studio.drawer(!studio.drawer.peek())}><text>Screens</text></view:button>
			</Show>
			<view tag="crumb" direction="row" align-items="center" column-gap={6} color={c("fg2")} shrink={1} min-width={0}>
				<Show when={!studio.compact()}>
					<text font-weight={Theme.MEDIUM} color={c("fg")}>{p == null ? "helder studio" : p.name}</text>
					<text color={c("fg3")}>/</text>
				</Show>
				<text tag="crumb-screen" max-lines={1} text-overflow="ellipsis">{crumb(studio)}</text>
			</view>
			<view slot="seg">
				<view:button tag="seg-design" slot="seg-item" role="button" label="Design" focusable data-on={studio.mode() != "code" ? "true" : "false"}
					onPress={() -> studio.setMode("design")}><text>Design</text></view:button>
				<view:button tag="seg-code" slot="seg-item" role="button" label="Code" focusable data-on={studio.mode() == "code" ? "true" : "false"}
					onPress={() -> studio.setMode("code")}><text>Code</text></view:button>
			</view>
			<view grow={1}/>
			<view direction="row" column-gap={2}>
				<view:button tag="undo" slot="button" role="button" label="Undo" focusable data-disabled={studio.docs.canUndo() ? "false" : "true"}
					onPress={() -> studio.undo()}><image src={Icons.undo} width={14} height={14}/></view:button>
				<view:button tag="redo" slot="button" role="button" label="Redo" focusable data-disabled={studio.docs.canRedo() ? "false" : "true"}
					onPress={() -> studio.redo()}><image src={Icons.redo} width={14} height={14}/></view:button>
			</view>
		</view>;
	}

	static function crumb(studio:Studio):String {
		var f = studio.focused();
		if (studio.mode() == "stories") return "Stories";
		if (f == null) return studio.mode() == "code" ? "Code" : "All screens";
		var s = studio.project == null ? null : Lambda.find(studio.project.screens, x -> x.name == f);
		return s == null ? f : s.label;
	}

	static function diagnosticsLabel(studio:Studio):String {
		var pr = studio.previews, f = studio.codeFile();
		if (pr == null || f == null) return "";
		var n = Lambda.count(pr.diagnostics(), d -> d.file == f);
		return n == 0 ? "" : '$n problem(s)';
	}

	public static function fileLabel(studio:Studio, f:Null<String>):String {
		if (f == null) return "";
		var p = studio.project;
		var rel = p != null && f.startsWith(p.dir + "/") ? f.substr(p.dir.length + 1) : haxe.io.Path.withoutDirectory(f);
		var sel = studio.selection();
		studio.docs.version();
		if (sel != null && sel.file == f) return rel + ":" + studio.docs.get(f).doc.lineCol(sel.start).line;
		return rel;
	}

	public static function slug(name:String):String
		return ~/[^A-Za-z0-9_-]+/g.replace(name, "-").toLowerCase();
}

// The studio's own actions (helder.ui.actions: secondary-z, secondary-shift-z, Escape)
enum StudioAction {
	Undo;
	Redo;
	Overview;
}

// (a sidebar's row: a flow's name, or one of its screens)
@:structInit class SidebarRow {
	public final key:String;
	public final flow:String;
	public final screen:Null<Project.ScreenInfo>;
}
