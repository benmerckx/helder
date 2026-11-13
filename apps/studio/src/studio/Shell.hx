package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.ui.view.UiFlow.VirtualList;
import helder.ui.widgets.WindowButtons;
import helder.ui.widgets.WindowButtons.WindowControls;
import studio.Theme.c;

using StringTools;

// The studio's window (Theme's look): the canvas under everything (Board),
// panels flush with the window around it: the sidebar (the window's
// buttons and the project in one row, its pages and frames, the layers),
// the inspector (Inspector) or the code (Code); the toolbar between them
// (a breadcrumb, the command field, undo and redo, Design and Code, Play),
// its empty parts dragging the window (an inset title bar: helder.os's). Compact (a phone, a tablet upright): a
// top bar above the canvas, the panels sheets over it (Sheets).
class Shell implements Markup {
	public static function view(studio:Studio):View {
		var p = studio.project;
		#if (hxmc.target == "wasm32-wasi")
		// (the browser without a project: the folder, the examples, OPFS's projects)
		if (p == null) return Welcome.view(studio);
		#end
		// (the app's: Escape and the rest work with nothing focused, the keymap starting at the root)
		onCleanup(helder.ui.actions.Actions.on(StudioAction, a -> {
			switch a {
				case Undo: studio.undo();
				case Redo: studio.redo();
				case Overview: studio.escape();
				case Jump: studio.commandOpen(!studio.commandOpen.peek());
				case FitAll: studio.fitAll();
				case FitSelection: studio.fitSelection();
			}
			true;
		}));
		return <view tag="studio" grow={1} ref={(n:Node) -> n.theme = Theme.sheet} background={c("canvas")} color={c("fg")} font-family={Theme.UI}
			font-size={Theme.BODY}>
			<For each={[studio.made()]}>{_ ->
				<Errored fallback={(e, _) -> {
					// (said after the making that threw: no signal written inside it)
					haxe.Timer.delay(() -> studio.crashed(e), 0);
					return <view grow={1}/>;
				}}>
					<Show when={studio.compact()} fallback={desktop(studio)}>{compact(studio)}</Show>
					<Show when={studio.commandOpen()}>{Command.view(studio)}</Show>
				</Errored>
			}</For>
			<For each={studio.crash() == null ? [] : [studio.crash()]}>{(k:Read<Crash>) -> Crash.view(studio, k(), () -> studio.reload())}</For>
		</view>;
	}

	// the canvas between the panels, flush with the window: the sidebar
	// left, the inspector (or the code) right, the toolbar above the canvas
	static function desktop(studio:Studio):View
		return <view tag="desktop" grow={1}>
			<view position="absolute" inset={0}>{Board.view(studio)}</view>
			{toolbar(studio)}
			<view tag="sidebar-card" slot="panel" position="absolute" left={0} top={0} bottom={0} width={Theme.SIDEBAR} border-width="0 1 0 0">
				{sidebar(studio)}
			</view>
			<Show when={studio.mode() == "code"}>{codeCard(studio)}</Show>
			<Show when={studio.mode() == "file"}>
				<view tag="file-card" slot="panel" position="absolute" left={Theme.SIDEBAR} right={0} top={Theme.HEADER} bottom={0}>{FileView.view(studio)}</view>
			</Show>
			<Show when={studio.playing() != null}>
				<view tag="player-card" slot="panel" position="absolute" left={Theme.SIDEBAR} right={0} top={Theme.HEADER} bottom={0} transition="fade scale(0.98)"
					motion="snappy"><view grow={1} min-height={0} instant>{Play.view(studio)}</view></view>
			</Show>
			<Show when={studio.mode() != "code" && studio.mode() != "file" && studio.playing() == null}>
				<view tag="inspector-card" slot="panel" position="absolute" right={0} top={0} bottom={0} width={Theme.INSPECTOR} border-width="0 0 0 1"
					onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>{Inspector.card(studio, true)}</view>
			</Show>
		</view>;

	// the code beside the canvas, between the sidebar and the frame shown
	static function codeCard(studio:Studio):View
		return <view tag="code" slot="panel" position="absolute" left={Theme.SIDEBAR} top={Theme.HEADER} bottom={0} width={codeWidth(studio)} border-width="0 1 0 0">
			<view tag="code-head" direction="row" align-items="center" column-gap={6} height={Theme.ROW + 6} padding={'0 ${Theme.PAD}'} border-width="0 0 1 0"
				border-color={c("line")} font-size={Theme.SMALL} color={c("fg2")} shrink={0}>
				<image src={Icons.fileCode} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("kind-code")}/>
				<text tag="code-file" font-family={Theme.CODE}>{fileLabel(studio, studio.codeFile())}</text>
				<view grow={1}/>
				<text tag="code-diagnostics" color={c("red")}>{diagnosticsLabel(studio)}</text>
			</view>
			{studio.editor}
		</view>;

	public static function codeWidth(studio:Studio):Float {
		studio.stageSize();
		return Math.round(Math.max(360, (studio.stageWidth - Theme.SIDEBAR) * 0.55));
	}

	// the toolbar between the panels: where you are, the command field, the buttons
	static function toolbar(studio:Studio):View {
		var wide = () -> studio.mode() == "code" || studio.mode() == "file" || studio.playing() != null;
		return <view tag="header" slot="panel" drag-region position="absolute" left={Theme.SIDEBAR} right={wide() ? 0 : Theme.INSPECTOR} top={0}
			height={Theme.HEADER} padding={'0 ${wide() && controlsRight() ? 0 : Theme.PAD - 4} 0 ${Theme.PAD}'} border-width="0 0 1 0" direction="row"
			align-items="center" column-gap={8} overflow="visible">
			{crumbs(studio)}
			<view grow={1} min-width={4}/>
			{commandField(studio)}
			<view grow={1} min-width={4}/>
			{buttons(studio)}
			<Show when={wide()}><WindowControls side="end"/></Show>
		</view>;
	}

	// the window's buttons at its top right (Windows', Linux's), the bar's padding there theirs
	public static function controlsRight():Bool
		return WindowButtons.side() == "end";

	// page / frame (the project is the sidebar's, above)
	static function crumbs(studio:Studio):View {
		return <view tag="crumb" direction="row" align-items="center" column-gap={4} shrink={0} max-width={280} color={c("fg2")}>
			<Show when={crumbPage(studio) == null}>
				<text tag="crumb-page" max-lines={1} text-overflow="ellipsis" color={c("fg2")}>{studio.mode() == "design" ? "All frames" : ""}</text>
			</Show>
			<Show when={crumbPage(studio) != null}>
				<text tag="crumb-page" shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis" cursor="pointer"
					onClick={_ -> if (studio.mode() == "design") studio.showPage(crumbPage(studio))}>{crumbPage(studio)}</text>
			</Show>
			<Show when={crumbFrame(studio) != null}>
				<image src={Icons.chevronRight} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("fg3")} shrink={0}/>
				<text tag="crumb-screen" shrink={0} max-lines={1} font-weight={Theme.MEDIUM} color={c("fg")}>{crumbFrame(studio)}</text>
			</Show>
		</view>;
	}

	// the command field: a frame, a file or a tool by name (secondary-K: ⌘K on macOS, in the browser too)
	static function commandField(studio:Studio):View
		return <view:button tag="command" slot="command" role="button" label="Jump to a frame, a file or a tool" focusable width={220} shrink={8}
			min-width={150} onPress={() -> studio.commandOpen(true)}>
			<image src={Icons.search} width={Theme.ICON_XS} height={Theme.ICON_XS} shrink={0}/>
			<text grow={1} shrink={0} max-lines={1}>Jump to…</text>
			<text slot="kbd" shrink={0}>{shortcut("K")}</text>
		</view:button>;

	// a shortcut as the platform writes it: ⌘K on macOS, Ctrl K elsewhere
	public static function shortcut(key:String):String
		return helder.ui.actions.Keymap.mac ? "⌘" + key : "Ctrl " + key;

	static function buttons(studio:Studio):View
		return <view direction="row" align-items="center" column-gap={2} shrink={0}>
			<view:button tag="undo" slot="button" role="button" label="Undo" focusable data-disabled={studio.docs.canUndo() ? "false" : "true"}
				onPress={() -> studio.undo()}><image src={Icons.undo} width={Theme.ICON_S} height={Theme.ICON_S}/></view:button>
			<view:button tag="redo" slot="button" role="button" label="Redo" focusable data-disabled={studio.docs.canRedo() ? "false" : "true"}
				onPress={() -> studio.redo()}><image src={Icons.redo} width={Theme.ICON_S} height={Theme.ICON_S}/></view:button>
			<view width={6}/>
			<view slot="seg">
				<view:button tag="seg-design" slot="seg-item" role="button" label="Design" focusable data-on={studio.mode() != "code" ? "true" : "false"}
					onPress={() -> studio.setMode("design")}><image src={Icons.penTool} width={Theme.ICON_XS} height={Theme.ICON_XS}/><text>Design</text></view:button>
				<view:button tag="seg-code" slot="seg-item" role="button" label="Code" focusable data-on={studio.mode() == "code" ? "true" : "false"}
					onPress={() -> studio.setMode("code")}><image src={Icons.code} width={Theme.ICON_XS} height={Theme.ICON_XS}/><text>Code</text></view:button>
			</view>
			<view width={6}/>
			{Play.button(studio)}
		</view>;

	// compact: the canvas under everything, a top bar (where you are, undo,
	// redo, Play), the sheets over it and the bar switching them (Sheets)
	static function compact(studio:Studio):View
		return <view tag="main" grow={1} min-width={0} background={c("canvas")}>
			<view position="absolute" inset={0}>{Board.view(studio)}</view>
			<view tag="header" drag-region position="absolute" left={0} right={0} top={0} height={Theme.TOPBAR} direction="row" align-items="center" column-gap={2}
				padding={'0 ${controlsRight() ? 0 : 6} 0 ${Theme.PAD + 2}'} background={c("bg")} border-width="0 0 1 0" border-color={c("line")}>
				<view tag="crumb" direction="row" align-items="center" shrink={1} min-width={0} grow={1}>
					<text tag="crumb-screen" max-lines={1} text-overflow="ellipsis" font-weight={Theme.MEDIUM}>{crumbFrame(studio) ?? crumbPage(studio) ?? (studio.project?.name ?? "helder studio")}</text>
				</view>
				<Show when={studio.playing() == null}>
					<view:button tag="undo" slot="button" role="button" label="Undo" focusable data-disabled={studio.docs.canUndo() ? "false" : "true"}
						onPress={() -> studio.undo()}><image src={Icons.undo} width={Theme.ICON} height={Theme.ICON}/></view:button>
					<view:button tag="redo" slot="button" role="button" label="Redo" focusable data-disabled={studio.docs.canRedo() ? "false" : "true"}
						onPress={() -> studio.redo()}><image src={Icons.redo} width={Theme.ICON} height={Theme.ICON}/></view:button>
				</Show>
				{Play.tools(studio)}
				{Play.button(studio)}
				<WindowControls side="end"/>
			</view>
			<Show when={studio.mode() == "file"}>
				<view position="absolute" left={0} right={0} top={Theme.TOPBAR} bottom={Theme.BAR} background={c("bg")}>{FileView.view(studio)}</view>
			</Show>
			<Show when={studio.playing() != null}>
				<view tag="player-page" position="absolute" left={0} right={0} top={Theme.TOPBAR} bottom={0} background={c("canvas")}>{Play.view(studio)}</view>
			</Show>
			<Show when={studio.sheet() != null}>{Sheets.view(studio)}</Show>
			<Show when={studio.playing() == null}>{Sheets.bar(studio)}</Show>
		</view>;

	// (top: the window's; its buttons in the project's row, not in a sheet,
	// nor without an inset title bar: the browser's, full screen)
	public static function sidebar(studio:Studio, top = true):View {
		var p = studio.project, bar = () -> top && WindowButtons.side() == "start";
		return <view tag="sidebar" grow={1} min-height={0}>
			<view tag="project" direction="row" align-items="center" column-gap={8} drag-region={top} height={Theme.HEADER} padding={'0 ${Theme.PAD}'}
				shrink={0} border-width="0 0 1 0" border-color={c("line")}>
				<Show when={bar()}><view tag="sidebar-top" direction="row" align-items="center" padding="0 6 0 0"><WindowControls/></view></Show>
				<text font-weight={Theme.MEDIUM} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis">{p == null ? "helder studio" : p.name}</text>
				<text font-size={Theme.SMALL} color={c("fg3")} shrink={0} max-lines={1}>{projectKind(p)}</text>
			</view>
			<view tag="nav" padding="6 6" shrink={0}>
				{nav(studio, "nav-all", "All frames", Icons.layoutGrid, () -> studio.mode() == "design" && studio.focused() == null, () -> {
					studio.lower();
					studio.setMode("design");
					studio.focus(null);
				})}
				{nav(studio, "nav-stories", "Stories", Icons.bookOpen, () -> studio.mode() == "stories", () -> {
					studio.lower();
					studio.setMode("stories");
				})}
			</view>
			<view tag="files" slot="section" grow={1} min-height={0} padding="4 6 6" row-gap={0}>
				<view slot="section-head" padding="0 8"><text>Files</text></view>
				<view grow={1} min-height={0}><VirtualList tag="screens" each={studio.tree == null ? [] : studio.tree.rows()} by={(r:FileTree.TreeRow) -> r.key}
					estimate={Theme.ROW} label="Files">{(r:Read<FileTree.TreeRow>, i:Int) -> treeRow(studio, r())}</VirtualList></view>
			</view>
			<Show when={studio.layers(studio.focused()) && studio.mode() != "stories"}>{Layers.view(studio)}</Show>
		</view>;
	}

	static function projectKind(p:Null<Project>):String {
		if (p == null) return "";
		var designs = p.designFiles().length, live = p.live().length;
		return designs > 0 && live == 0 ? "design files" : p.typescript ? "TypeScript" : "Haxe";
	}

	// a row of the tree: a folder (opens and closes), a file (opens in its
	// view; an image dragged onto a design's frame inserts it), a frame
	// under its file (focused on the canvas)
	static function treeRow(studio:Studio, r:FileTree.TreeRow):View {
		var e = r.entry, info = r.screen, tree = studio.tree;
		var pad = '0 8 0 ${4 + r.depth * 12}';
		if (info != null)
			return <view:button tag={"nav-screen-" + slug(info.name)} slot="nav-item" padding={pad} role="button" label={info.name} focusable
				data-on={studio.focused() == info.name ? "true" : "false"} onPress={() -> {
					studio.lower();
					if (studio.mode() != "design") studio.setMode("design");
					studio.focus(info.name);
				}}>
				<view width={Theme.ICON_XS}/>
				<image src={Icons.frame} width={Theme.ICON_S} height={Theme.ICON_S} color={studio.focused() == info.name ? c("accent-ink") : c("fg3")}/>
				<text max-lines={1} text-overflow="ellipsis">{info.label}</text>
			</view:button>;
		var on = studio.focused() == null && studio.shown() == e.path;
		return <view:button tag={tree.tag(e.path)} slot="nav-item" padding={pad} role="button" label={tree.relative(e.path)} focusable
			data-on={on ? "true" : "false"} drag-data={e.kind == Image ? e.path : null} onPress={() -> studio.openFile(e)}>
			<view tag={"toggle-" + slug(tree.relative(e.path))} width={Theme.ICON_XS} align-self="stretch" align-items="center" justify="center"
				onClick={ev -> if (r.hasChildren) {
					ev.stop();
					tree.toggle(e);
				}}>
				{r.hasChildren ? <image src={tree.open(e) ? Icons.chevronDown : Icons.chevronRight} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("fg3")}/> : null}
			</view>
			<image src={e.kind == Dir && tree.open(e) ? Icons.folderOpen : FileView.icon(e.kind)} width={Theme.ICON_S} height={Theme.ICON_S}
				color={on ? c("accent-ink") : c(FileView.hue(e.kind))}/>
			<text max-lines={1} text-overflow="ellipsis">{e.name}</text>
		</view:button>;
	}

	static function nav(studio:Studio, tag:String, label:String, icon:helder.ui.Svg, on:Void->Bool, press:Void->Void):View
		return <view:button tag={tag} slot="nav-item" role="button" label={label} focusable data-on={on() ? "true" : "false"} onPress={() -> press()}>
			<image src={icon} width={Theme.ICON_S} height={Theme.ICON_S} color={on() ? c("accent-ink") : null}/>
			<text>{label}</text>
		</view:button>;

	// (the breadcrumb's page and frame: the focused frame's, else none)
	static function crumbPage(studio:Studio):Null<String> {
		if (studio.mode() == "stories") return "Stories";
		var shown = studio.shown();
		if ((studio.mode() == "file" || studio.mode() == "code") && shown != null && studio.tree != null && studio.focused() == null) return studio.tree.relative(shown);
		var f = studio.focused(), s = f == null ? null : studio.project?.screen(f);
		return s == null ? null : s.flow;
	}

	static function crumbFrame(studio:Studio):Null<String> {
		if (studio.mode() == "stories") return null;
		var f = studio.focused(), s = f == null ? null : studio.project?.screen(f);
		return s == null ? f : s.label;
	}

	static function diagnosticsLabel(studio:Studio):String {
		var pr = studio.previews, f = studio.codeFile();
		if (pr == null || f == null) return "";
		var n = Lambda.count(pr.diagnostics(), d -> d.file == f);
		return n == 0 ? "" : n == 1 ? "1 problem" : '$n problems';
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

// The studio's own actions (helder.ui.actions: secondary-z, secondary-shift-z, Escape, secondary-k, shift-1, shift-2)
enum StudioAction {
	Undo;
	Redo;
	Overview;
	Jump;
	FitAll;
	FitSelection;
}

