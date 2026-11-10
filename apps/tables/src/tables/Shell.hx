package tables;

import helder.ui.*;
import helder.ui.widgets.DataGrid;
import helder.ui.widgets.EditableText;
import helder.ui.widgets.Theme;
import helder.ui.widgets.Theme.c;
import helder.ui.widgets.WindowButtons.WindowControls;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import tables.Tables.Entry;

// The window: the sidebar (the database, a search, its tables with their
// counts, a dot where changes are not saved), the open table's header
// (Back, its name and count, Data, Structure and SQL), its filter and
// actions, the grid and the row panel beside it, the changes' bar
// (Discard, Save), the status bar; while there is no server, how to start
// one; a menu over everything
class Shell implements Markup {
	public static inline var SIDEBAR = 240;
	public static inline var PANEL = 320;

	public static function view(app:Tables):View
		return <view slot="body" grow={1} direction="row" min-height={0}>
			{sidebar(app)}
			<view tag="main" grow={1} min-width={0} direction="column">
				{header(app)}
				<Switch>
					<Match when={app.state() == "offline"}>{waiting(app)}</Match>
					<Match when={app.state() == "connecting"}><view grow={1} background={c("bg")}/></Match>
					<Match when={app.mode() == "data"}>{data(app)}</Match>
					<Match when={app.mode() == "structure"}>{structure(app)}</Match>
					<Match when={app.mode() == "sql"}>{console(app)}</Match>
				</Switch>
				{status(app)}
			</view>
			<Show when={app.menu() != null}>{menu(app)}</Show>
		</view>;

	static function icon(src:Svg, color:Color, size = Theme.ICON_S):View
		return <image src={src} width={size} height={size} color={color} shrink={0}/>;

	static inline function primaryKey(key:String):String
		return (helder.ui.actions.Keymap.mac ? "⌘" : "Ctrl+") + key;

	// ---- the sidebar

	static var searchField:Null<Node> = null;

	public static function focusSearch()
		if (searchField != null) searchField.focus();

	static function sidebar(app:Tables):View {
		var shown = () -> {
			var q = app.search().toLowerCase();
			return app.tables().filter(t -> q == "" || t.id.toLowerCase().indexOf(q) >= 0);
		};
		return <view tag="sidebar" slot="panel" width={SIDEBAR} shrink={0} border-width="0 1 0 0">
			<view tag="database" direction="row" align-items="center" column-gap={8} drag-region height={Theme.HEADER} padding={'0 ${Theme.PAD}'} shrink={0}
				border-width="0 0 1 0" border-color={c("line")}>
				<Show when={SafeArea.titlebar() != null}><view direction="row" align-items="center" padding="0 6 0 0"><WindowControls/></view></Show>
				{icon(Icons.database, c("fg3"))}
				<text font-weight={Theme.MEDIUM} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis">{database(app)}</text>
				<view grow={1}/>
				<text font-size={Theme.SMALL} color={c("fg3")} shrink={0} max-lines={1}>{driver(app)}</text>
			</view>
			<view padding="8 8 4" shrink={0}>
				<view slot="field" onClick={_ -> focusSearch()}>
					{icon(Icons.search, c("fg3"), 12)}
					<field tag="search" slot="field-input" font-family={Theme.UI} label="Search tables" placeholder="Search tables" value={app.search}
						ref={(n:Node) -> searchField = n} onInput={e -> app.search(e.text)} onKeyDown={e -> {
							if (e.key == Key.ENTER) {
								var first = shown()[0];
								if (first != null) app.open(first);
							}
							if (e.key == Key.ESCAPE) {
								app.search("");
								app.grid.focus();
							}
						}}/>
					<text slot="kbd" padding="0 8 0 0">{primaryKey("K")}</text>
				</view>
			</view>
			<scroll tag="tables" grow={1} min-height={0} padding="4 8 8" row-gap={1} role="list" label="Tables">
				<For each={groups(shown())}>{(group:Read<{schema:String, tables:Array<Table>}>) -> {
					var g = group();
					<view row-gap={1}>
						<view slot="section-head" padding="0 8"><text font-size={Theme.SMALL}>{g.schema == "" ? "Tables" : g.schema}</text></view>
						<For each={g.tables}>{(table:Read<Table>) -> tableItem(app, table())}</For>
					</view>;
				}}</For>
				<Show when={app.state() == "ready" && shown().length == 0}>
					<text color={c("fg3")} padding="6 8">{app.tables().length == 0 ? "No tables yet" : "No table matches"}</text>
				</Show>
			</scroll>
		</view>;
	}

	// (the tables by schema, a heading each when there are several)
	static function groups(list:Array<Table>):Array<{schema:String, tables:Array<Table>}> {
		var out:Array<{schema:String, tables:Array<Table>}> = [];
		for (t in list) {
			var s = t.schema == "main" ? "" : t.schema;
			var last = out[out.length - 1];
			if (last == null || last.schema != s) out.push(last = {schema: s, tables: []});
			last.tables.push(t);
		}
		if (out.length == 1) out[0] = {schema: "", tables: out[0].tables};
		return out;
	}

	static function tableItem(app:Tables, t:Table):View
		return <view:button tag={"table-" + t.id} slot="nav-item" role="listitem" label={t.name} focusable data-on={(app.opening() ?? app.current()) == t ? "true" : "false"}
			onPress={() -> {
				if (app.mode() == "sql") app.mode("data");
				app.open(t);
			}}>
			{icon(t.view ? Icons.view : Icons.table, (app.opening() ?? app.current()) == t ? c("accent-ink") : c("fg3"))}
			<text grow={1} min-width={0} max-lines={1} text-overflow="ellipsis">{t.name}</text>
			<Show when={app.pending(t)}><view width={6} height={6} radius={3} background={c("sand")} label="Changes not saved"/></Show>
			<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg3")} font-variant-numeric="tabular-nums">
				{app.tables() == null || t.count < 0 ? "" : Format.count(t.count)}</text>
		</view:button>;

	static function database(app:Tables):String {
		var s = app.setup();
		if (s == null) return app.state() == "offline" ? "Not connected" : "";
		var name = s.database ?? "";
		if (name != "") return name;
		return switch s.dialect {
			case "sqlite": "SQLite";
			case "postgresql": "PostgreSQL";
			case "mysql": "MySQL";
			case "singlestore": "SingleStore";
			case d: d;
		}
	}

	// (the driver drizzle-kit uses: its package's last part)
	static function driver(app:Tables):String {
		var d = app.setup()?.driver ?? "";
		var slash = d.lastIndexOf("/");
		return slash >= 0 ? d.substr(slash + 1) : d;
	}

	// ---- the header

	static function header(app:Tables):View
		return <view tag="header" slot="panel" direction="row" align-items="center" column-gap={6} drag-region height={Theme.HEADER} shrink={0}
			padding={'0 ${Theme.PAD} 0 8'} border-width="0 0 1 0">
			<Show when={app.canBack()}>
				<view:button tag="back" slot="button" role="button" label="Back" focusable onPress={app.back}>{icon(Icons.back, c("fg2"), Theme.ICON)}</view:button>
			</Show>
			<view direction="row" align-items="baseline" column-gap={8} padding="0 4" min-width={0} shrink={1}>
				<text font-weight={Theme.MEDIUM} font-size={13} max-lines={1} text-overflow="ellipsis">{app.current()?.id ?? ""}</text>
				<text color={c("fg3")} font-variant-numeric="tabular-nums" shrink={0}>{rowsText(app)}</text>
			</view>
			<view grow={1}/>
			<Show when={app.state() == "ready"}>
				<view slot="seg" role="tablist" label="View">
					{seg(app, "data", "Data", Icons.table)}
					{seg(app, "structure", "Structure", Icons.columns)}
					{seg(app, "sql", "SQL", Icons.terminal)}
				</view>
				<view:button tag="refresh" slot="button" role="button" label="Refresh" focusable onPress={() -> app.mode() == "sql" ? app.run() : app.refresh()}>
					{icon(Icons.refresh, c("fg2"))}
				</view:button>
			</Show>
		</view>;

	static function rowsText(app:Tables):String {
		var n = app.count(), t = app.current();
		if (t == null || n < 0) return "";
		var total = t.count;
		var text = n == 1 ? "1 row" : '${Format.count(n)} rows';
		return app.applied() != "" && total >= 0 ? '$text of ${Format.count(total)}' : text;
	}

	static function seg(app:Tables, mode:String, label:String, src:Svg):View
		return <view:button tag={"mode-" + mode} slot="seg-item" role="tab" label={label} focusable selected={app.mode() == mode}
			data-on={app.mode() == mode ? "true" : "false"} onPress={() -> {
				app.mode(mode);
				if (mode == "sql") app.editor.view.focus(false) else if (mode == "data") app.grid.focus(false);
			}}>
			{icon(src, app.mode() == mode ? c("accent-ink") : c("fg3"), 12)}
			<text>{label}</text>
		</view:button>;

	// ---- the rows

	static function data(app:Tables):View
		return <view grow={1} min-height={0}>
			<view tag="toolbar" direction="row" align-items="center" column-gap={6} height={40} padding={'0 ${Theme.PAD}'} shrink={0}
				border-width="0 0 1 0" border-color={c("line")}>
				<view slot="field" grow={1} max-width={640} data-error={app.filterFailed() ? "true" : "false"} onClick={_ -> filterField?.focus()}>
					<text slot="field-label" font-family={Theme.CODE}>WHERE</text>
					<field tag="filter" slot="field-input" label="Filter" placeholder={example(app)} value={app.filter} ref={(n:Node) -> filterField = n}
						onInput={e -> app.filter(e.text)} onKeyDown={e -> {
							if (e.key == Key.ENTER) app.applyFilter();
							if (e.key == Key.ESCAPE) {
								if (app.filter.peek() != app.applied.peek()) app.filter(app.applied.peek()) else if (app.applied.peek() != "") app.clearFilter();
								app.grid.focus();
							}
						}}/>
					<Show when={app.applied() != "" || app.filter() != ""}>
						<view:button tag="clear-filter" slot="button" role="button" label="Clear filter" focusable height={20} min-width={20} padding={0}
							onPress={app.clearFilter}>{icon(Icons.close, c("fg3"), 12)}</view:button>
					</Show>
				</view>
				<Show when={app.filter() != app.applied()}><text color={c("fg3")} font-size={Theme.SMALL}>Enter to apply</text></Show>
				<view grow={1}/>
				<Show when={!(app.current()?.readOnly ?? true)} fallback={<text color={c("fg3")} font-size={Theme.SMALL}>{readOnlyText(app)}</text>}>
					<view:button tag="add-row" slot="button" role="button" label="Add row" focusable onPress={app.addRow}>
						{icon(Icons.plus, c("fg2"))}<text>Add row</text>
					</view:button>
					<view:button tag="delete-rows" slot="button" role="button" label="Delete selected rows" focusable onPress={app.deleteRows}>
						{icon(Icons.trash, c("fg2"))}<text>Delete</text>
					</view:button>
				</Show>
				<view:button tag="toggle-panel" slot="button" role="button" label="Row panel" focusable data-on={app.panel() ? "true" : "false"}
					onPress={() -> app.panel(!app.panel.peek())}>
					{icon(Icons.panel, app.panel() ? c("accent-ink") : c("fg2"))}
				</view:button>
			</view>
			<view direction="row" grow={1} min-height={0}>
				<view grow={1} min-width={0}>{app.grid}</view>
				<Show when={app.panel()}>{panel(app)}</Show>
			</view>
			<Show when={app.changes() > 0}>
				<view tag="changes" slot="panel" direction="row" align-items="center" column-gap={8} height={44} padding={'0 ${Theme.PAD}'} shrink={0}
					border-width="1 0 0 0" live="polite">
					<view width={6} height={6} radius={3} background={c("sand")}/>
					<text>{app.changes() == 1 ? "1 unsaved change" : '${app.changes()} unsaved changes'}</text>
					<text color={c("fg3")} font-size={Theme.SMALL}>{primaryKey("Z") + " to undo"}</text>
					<view grow={1}/>
					<view:button tag="discard" slot="button" role="button" label="Discard changes" focusable onPress={app.discard}>
						{icon(Icons.undo, c("fg2"))}<text>Discard</text>
					</view:button>
					<view:button tag="save" slot="primary" role="button" label="Save changes" focusable onPress={app.save}>
						<text>{app.saving() ? "Saving…" : "Save changes"}</text>
						<text color="rgba(255,255,255,0.65)" font-weight={400}>{primaryKey("S")}</text>
					</view:button>
				</view>
			</Show>
		</view>;

	static var filterField:Null<Node> = null;

	// the filter field focused (end: the caret after its text)
	public static function focusFilter(end = false) {
		var f = filterField;
		if (f == null) return;
		f.focus();
		if (end) haxe.Timer.delay(() -> if (Std.isOfType(f, EditableText)) {
			var t:EditableText = cast f;
			t.select(t.text.length, t.text.length);
		}, 0);
	}

	static function example(app:Tables):String {
		var t = app.current();
		if (t == null || t.columns.length == 0) return "";
		var c = t.columns.filter(c -> !c.primary && !c.numeric)[0] ?? t.columns[0];
		return '"${c.name}" = \'…\'';
	}

	static function readOnlyText(app:Tables):String {
		var t = app.current();
		return t == null ? "" : t.view ? "A view: read only" : "No primary key: read only";
	}

	// ---- the row panel: the cursor's row, a field a column, its relations

	static function panel(app:Tables):View {
		var t = app.current();
		if (t == null) return null;
		return <view tag="row-panel" slot="panel" width={PANEL} shrink={0} border-width="0 0 0 1">
			<view direction="row" align-items="center" column-gap={6} height={36} padding={'0 6 0 ${Theme.PAD}'} shrink={0}>
				<text font-weight={Theme.MEDIUM} grow={1}>{app.panelRow() < 0 ? "No row" : 'Row ${Format.count(app.panelRow() + 1)}'}</text>
				<text color={c("fg3")} font-size={Theme.SMALL}>{t.readOnly ? "read only" : ""}</text>
				<view:button tag="close-panel" slot="button" role="button" label="Close the row panel" focusable onPress={() -> app.panel(false)}>
					{icon(Icons.close, c("fg3"), 12)}
				</view:button>
			</view>
			<scroll grow={1} min-height={0} scrollbar-width="thin" scrollbar-color={c("edge")}>
				<view slot="section" row-gap={4}>
					<view slot="section-head"><text>Fields</text></view>
					<For each={[for (k in 0...t.columns.length) k]}>{(k:Read<Int>) -> fieldRow(app, t, k())}</For>
				</view>
				<Show when={app.links().length > 0}>
					<view slot="section" row-gap={1}>
						<view slot="section-head"><text>Relations</text></view>
						<For each={app.links()}>{(l:Read<{label:String, detail:String, run:Void->Void}>) -> {
							var link = l();
							<view:button slot="nav-item" role="link" label={link.label} focusable onPress={link.run}>
								{icon(Icons.link, c("fg3"), 12)}
								<text color={c("fg")} shrink={0}>{link.label}</text>
								<text color={c("fg3")} font-size={Theme.SMALL} min-width={0} max-lines={1} text-overflow="ellipsis">{link.detail}</text>
							</view:button>;
						}}</For>
					</view>
				</Show>
			</scroll>
		</view>;
	}

	// (a field's label inside it, as the studio's inspector's: as wide as the others, cut when longer)
	static inline var LABEL = 76;

	// a column's field: its name inside, its value (the code's font); JSON
	// and long text in a taller one, its name above; a dot when changed
	static function fieldRow(app:Tables, t:Table, k:Int):View {
		var col = t.columns[k];
		// (several lines: JSON, and text that is long or has lines of its own)
		var long = () -> {
			if (col.mode == "json" || col.type.toLowerCase().indexOf("json") >= 0) return true;
			var t = app.fieldText(k);
			return t != null && (t.length > 40 || t.indexOf("\n") >= 0);
		};
		var typed:Null<String> = null;
		function keep() {
			if (typed != null) app.setField(k, typed);
			typed = null;
		}
		function label():View
			return <view direction="row" align-items="center" column-gap={4} width={LABEL} shrink={0}>
				<text slot="field-label" min-width={0} shrink={1} max-lines={1} text-overflow="ellipsis">{col.name}</text>
				<Show when={app.fieldFlags(k) & DataGrid.EDITED != 0}><view width={5} height={5} radius={3} background={c("sand")} shrink={0}/></Show>
			</view>;
		return <Show when={long()} fallback={
			<view slot="field">
				{label()}
				<field slot="field-input" label={col.name} value={app.fieldText(k) ?? ""} placeholder={placeholder(app, k)} readonly={t.readOnly}
					onInput={e -> typed = e.text} onBlur={_ -> keep()} onKeyDown={e -> if (e.key == Key.ENTER) keep()}/>
			</view>
		}>
			<view slot="field" variant="tall">
				<view padding="2 0 0" shrink={0}>{label()}</view>
				<field:textarea slot="field-input" variant="tall" spellcheck="false" max-height={240} label={col.name} value={app.fieldText(k) ?? ""}
					placeholder={placeholder(app, k)} readonly={t.readOnly} onInput={e -> typed = e.text} onBlur={_ -> keep()}
					onKeyDown={e -> if (e.key == Key.ENTER && e.mods & (Key.MOD_META | Key.MOD_CONTROL) != 0) keep()}/>
			</view>
		</Show>;
	}

	static function placeholder(app:Tables, k:Int):String {
		var f = app.fieldFlags(k);
		return f & DataGrid.DEFAULT != 0 ? "DEFAULT" : f & DataGrid.NULL != 0 ? "NULL" : "";
	}

	// ---- the structure, the console

	static function structure(app:Tables):View
		return <view grow={1} min-height={0}>{app.structure}</view>;

	static function console(app:Tables):View
		return <view grow={1} min-height={0}>
			<view height="38%" min-height={120} shrink={0} padding="8 0 0" background={c("bg")}>{app.editor}</view>
			<view direction="row" align-items="center" column-gap={10} height={40} padding={'0 ${Theme.PAD}'} shrink={0} border-width="1 0 1 0"
				border-color={c("line")} background={c("bg")}>
				<view:button tag="run" slot="primary" role="button" label="Run query" focusable onPress={app.run}>
					{icon(Icons.play, c("accent-fg"), 12)}<text>Run</text>
					<text color="rgba(255,255,255,0.65)" font-weight={400}>{primaryKey("↵")}</text>
				</view:button>
				<text color={app.resultFailed() ? c("red") : c("fg3")} max-lines={2} text-overflow="ellipsis" min-width={0} shrink={1} selectable>
					{app.resultNote}</text>
			</view>
			<view grow={1} min-height={0}>{app.results}</view>
		</view>;

	// ---- no server yet

	static function waiting(app:Tables):View
		return <view grow={1} align-items="center" justify="center" padding={24} background={c("bg")}>
			<view width={420} max-width="100%" row-gap={12}>
				<text font-size={15} font-weight={Theme.MEDIUM}>Waiting for drizzle-kit studio</text>
				<text color={c("fg2")} line-height={1.5}>Run Drizzle's studio server in your project. This window connects to it as soon as it starts.</text>
				<view slot="field" height={32} padding="0 12" cursor="default">
					<text font-family={Theme.CODE} color={c("fg")} selectable>npx drizzle-kit studio</text>
				</view>
				<text color={c("fg3")} font-size={Theme.SMALL}>{'Looking at ${app.url}'}</text>
			</view>
		</view>;

	// ---- the status bar

	static function status(app:Tables):View
		return <view tag="status" slot="panel" direction="row" align-items="center" column-gap={12} height={26} padding={'0 ${Theme.PAD}'} shrink={0}
			border-width="1 0 0 0" font-size={Theme.SMALL} color={c("fg3")}>
			<Show when={app.note() == ""} fallback={
				<text tag="note" color={app.failed() ? c("red") : c("fg2")} max-lines={1} text-overflow="ellipsis" min-width={0} shrink={1} selectable live="polite">
					{app.note}</text>
			}>
				<text max-lines={1} min-width={0}>{app.state() == "ready" ? "Connected" : app.state() == "offline" ? "Not connected" : "Connecting"}</text>
			</Show>
			<view grow={1}/>
			<Show when={app.mode() == "data"}>
				<text max-lines={1} font-variant-numeric="tabular-nums">{app.cell}</text>
				<text max-lines={1} font-variant-numeric="tabular-nums">{app.took() > 0 ? '${Math.round(app.took() * 1000)} ms' : ""}</text>
			</Show>
		</view>;

	// ---- a menu: its items, Up and Down between them, Enter, Escape; kept inside the window

	static function menu(app:Tables):View {
		var m = app.menu();
		// (the items' nodes, in order, and their items)
		var nodes:Array<Node> = [], entries:Array<Entry> = [];
		var first = m.items.filter(i -> i.on)[0] ?? m.items.filter(i -> !i.line && !i.disabled)[0];
		function close() {
			app.menu(null);
			app.grid.focus(false);
		}
		function step(d:Int) {
			var on = nodes.filter(n -> n.focused)[0];
			var i = on == null ? (d > 0 ? -1 : nodes.length) : nodes.indexOf(on);
			do
				i += d
			while (i >= 0 && i < nodes.length && entries[i].disabled);
			if (i >= 0 && i < nodes.length) nodes[i].focus();
		}
		return <view tag="menu-layer" position="absolute" inset={0} onPointerDown={_ -> close()}>
			<view tag="menu" slot="floating" position="absolute" left={m.x} top={m.y} min-width={Math.max(200, m.width ?? 0)} max-height={420}
				shadow={Theme.popover()} role="menu" onPointerDown={e -> e.stop()} onResize={e -> inside(e.target)}
				onKeyDown={e -> switch e.key {
					case Key.ESCAPE: close();
					case Key.DOWN:
						step(1);
						e.preventDefault();
					case Key.UP:
						step(-1);
						e.preventDefault();
					case _:
				}}>
				<scroll min-height={0} shrink={1}>
					<For each={m.items}>{(item:Read<Entry>) -> {
						var i = item();
						i.line ? <view height={1} margin="4 4" background={c("line")}/> : <view:button slot="menu-item" role="menuitem" label={i.label} focusable
							data-disabled={i.disabled ? "true" : "false"} selected={i.on} ref={(n:Node) -> {
								nodes.push(n);
								entries.push(i);
								if (i == first) haxe.Timer.delay(() -> n.focus(false), 0);
							}} onPress={() -> {
								if (i.disabled) return;
								close();
								i.run();
							}}>
							<view width={Theme.ICON_S} shrink={0}>{i.on ? icon(Icons.check, c("accent-ink")) : i.icon == null ? null : icon(i.icon, c("fg3"))}</view>
							<text grow={1} max-lines={1} color={i.muted ? c("fg3") : c("fg")}>{i.label}</text>
							<text color={c("fg3")} font-size={Theme.SMALL}>{i.detail ?? ""}</text>
						</view:button>;
					}}</For>
				</scroll>
			</view>
		</view>;
	}

	// (a menu moved inside the window when it would go past its right or bottom edge)
	static function inside(n:Node) {
		var layer = n.parent;
		if (layer == null || n.ui == null) return;
		var w = layer.width, h = layer.height;
		if (n.x + n.width > w - 8) n.style.left = Math.max(8, w - n.width - 8);
		if (n.y + n.height > h - 8) n.style.top = Math.max(8, h - n.height - 8);
	}
}
