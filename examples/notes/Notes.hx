// title: Notes
// summary: A notes app recreated whole: folders, a list that moves as notes are pinned, added and deleted, an editor in Inter, a command launcher (Ctrl/Cmd+K) that fuzzy-finds commands and notes, the keyboard throughout, a dark theme morphing through OKLab
// tags: ui, view, motion, app, keyboard, showcase
// demo: canvas 1280x720
import helder.ui.Key;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

typedef Note = {
	id:Int,
	folder:String,
	title:Signal<String>,
	body:Signal<String>,
	pinned:Signal<Bool>,
	// minutes since it was edited
	edited:Signal<Int>
}

typedef Command = {
	label:String,
	kind:String,
	keys:String,
	run:Void->Void
}

// A notes app: the sidebar's folders, the list of the folder's notes
// (pinned first; keyed rows, so a pin, a new note or a delete moves the
// others on springs), the note open in the editor (its title and body
// text fields, its words counted), and the launcher: Ctrl+K (Cmd+K on a
// Mac) opens it over the app, what is typed finds commands and notes by
// their letters in order, the arrows pick, Enter runs, Escape closes.
// Ctrl+N makes a note, Ctrl+P pins, Ctrl+D turns the lights down;
// Alt+Up and Alt+Down walk the list. examples/notes/demo.json drives it
// headless.
class Notes implements Markup {
	static final FOLDERS = ["All notes", "Ideas", "Work", "Travel", "Recipes"];

	static var nextId = 0;

	static function note(folder:String, title:String, body:String, edited:Int, pinned = false):Note
		return {id: nextId++, folder: folder, title: signal(title), body: signal(body), pinned: signal(pinned), edited: signal(edited)};

	static final notes:Signal<Array<Note>> = signal([
		note("Work", "Launch checklist", "Freeze the release branch on Tuesday.\nCanary to 5% on Wednesday morning, watch p99 and the error budget.\nStatus page copy: short, honest, no adjectives.\nThank the on-call rotation in the channel.", 12, true),
		note("Ideas", "A garden that answers back", "Soil sensors in each bed, a tiny screen on the shed door.\nIt only ever says one thing: what to do today.\n\"Water the beans.\" \"Leave the tomatoes alone.\"", 48),
		note("Travel", "Lisbon in October", "Tram 28 before nine, or not at all.\nMiradouro da Graça at sunset.\nPastéis at Manteigaria, not the famous place.\nBook the Sintra train the day before.", 95),
		note("Recipes", "Brown butter cookies", "Brown 225 g butter until it smells of hazelnuts, cool it.\n200 g dark brown sugar, 100 g white, two eggs, vanilla.\n300 g flour, a teaspoon of soda, salt.\nRest the dough overnight. Bake at 180 for 11 minutes.", 180),
		note("Work", "1:1 with Mira", "She wants to own the importer rewrite.\nAsk about the conference talk.\nShe is right about the flaky tests.", 260),
		note("Ideas", "Names for the boat", "Second Wind\nPaper Moon\nKnot Today\nThe Unsinkable II", 1440),
		note("Travel", "Packing for the Alps", "Shell, fleece, the good socks.\nHead torch, spare batteries.\nSun cream, because the snow is a mirror.", 2880),
		note("Recipes", "Green shakshuka", "Leeks, spinach, a lot of herbs.\nCumin and chilli flakes.\nEggs in wells, lid on, four minutes.\nFeta and lemon at the end.", 4320)
	]);

	static final folder = signal("All notes");
	static final selected = signal(0);
	static final dark = signal(false);
	static final launcher = signal(false);
	static final query = signal("");
	static final pick = signal(0);

	// the theme's colours
	static function c(light:String, darkColor:String):String
		return dark() ? darkColor : light;

	static function shown():Array<Note> {
		var f = folder();
		var list = [for (n in notes()) if (f == "All notes" || n.folder == f) n];
		list.sort((a, b) -> a.pinned() == b.pinned() ? a.edited() - b.edited() : a.pinned() ? -1 : 1);
		return list;
	}

	static function current():Null<Note> {
		for (n in notes())
			if (n.id == selected()) return n;
		return null;
	}

	static function ago(m:Int):String
		return m < 1 ? "now" : m < 60 ? m + " min" : m < 1440 ? Std.int(m / 60) + " h" : Std.int(m / 1440) + " d";

	static function words(s:String):Int {
		var n = 0, inWord = false;
		for (i in 0...s.length) {
			var ch = s.charCodeAt(i), w = ch != 32 && ch != 10 && ch != 9;
			if (w && !inWord) n++;
			inWord = w;
		}
		return n;
	}

	// --- the commands

	public static function newNote() {
		var f = folder() == "All notes" ? "Ideas" : folder();
		var n = note(f, "Untitled", "", 0);
		notes([n].concat(notes()));
		selected(n.id);
	}

	public static function togglePin() {
		var n = current();
		if (n != null) n.pinned(!n.pinned());
	}

	public static function deleteNote() {
		var n = current();
		if (n == null) return;
		var list = shown(), at = list.indexOf(n);
		notes(notes().filter(x -> x != n));
		var rest = shown();
		if (rest.length > 0) selected(rest[Std.int(Math.min(at, rest.length - 1))].id);
	}

	static function step(d:Int) {
		var list = shown(), n = current(), at = n == null ? -1 : list.indexOf(n);
		if (list.length > 0) selected(list[Std.int(Math.max(0, Math.min(list.length - 1, at + d)))].id);
	}

	static function commands():Array<Command> {
		var n = current();
		var out:Array<Command> = [
			{label: "New note", kind: "Command", keys: "Ctrl N", run: newNote},
			{label: n != null && n.pinned() ? "Unpin note" : "Pin note", kind: "Command", keys: "Ctrl P", run: togglePin},
			{label: dark() ? "Light theme" : "Dark theme", kind: "Command", keys: "Ctrl D", run: () -> dark(!dark())},
			{label: "Delete note", kind: "Command", keys: "", run: deleteNote}
		];
		for (f in FOLDERS)
			out.push({label: "Go to " + f, kind: "Folder", keys: "", run: () -> folder(f)});
		for (x in notes())
			out.push({label: x.title(), kind: x.folder, keys: "", run: () -> {
				folder("All notes");
				selected(x.id);
			}});
		return out;
	}

	// how well query's letters appear in order in s (-1: not all); earlier, closer runs score more
	static function score(q:String, s:String):Int {
		if (q == "") return 0;
		var a = q.toLowerCase(), b = s.toLowerCase(), at = 0, total = 0, last = -2;
		for (i in 0...a.length) {
			var ch = a.charAt(i);
			if (ch == " ") continue;
			var k = b.indexOf(ch, at);
			if (k < 0) return -1;
			total += k == last + 1 ? 8 : k == 0 || b.charAt(k - 1) == " " ? 6 : 1;
			last = k;
			at = k + 1;
		}
		return total * 100 - b.length;
	}

	static function found():Array<Command> {
		var q = query(), all = commands();
		var scored = [for (c in all) {c: c, s: score(q, c.label)}].filter(x -> x.s >= 0);
		if (q != "") scored.sort((x, y) -> y.s - x.s);
		return [for (i in 0...Std.int(Math.min(7, scored.length))) scored[i].c];
	}

	static function run(k:Int) {
		var list = found();
		if (k >= 0 && k < list.length) {
			closeLauncher();
			list[k].run();
		}
	}

	static var app:Null<helder.ui.Node> = null;

	// the launcher closed, the keys back to the app
	static function closeLauncher() {
		launcher(false);
		if (app != null) app.focus(false);
	}

	static function openLauncher() {
		query("");
		pick(0);
		launcher(true);
	}

	// --- the views

	static function Folder(props:{name:String}):View
		return <view tag={"folder-" + props.name.split(" ")[0].toLowerCase()} role="button" focusable cursor="pointer" direction="row" align-items="center"
			padding="8 12" radius={8} background={folder() == props.name ? c("#e8eaf2", "#232838") : c("#00000000", "#00000000")} onPress={() -> folder(props.name)}>
			<text grow={1} font-size={14} font-weight={folder() == props.name ? 600 : 450}>{props.name}</text>
			<text font-size={12} color={c("#8b90a0", "#7d849c")} font-variant-numeric="tabular-nums">{
				"" + [for (n in notes()) if (props.name == "All notes" || n.folder == props.name) n].length
			}</text>
		</view>;

	static function Item(props:{note:Note}):View {
		var n = props.note;
		return <view tag={"note-" + n.id} role="option" selected={selected() == n.id} focusable cursor="pointer" padding="12 14" radius={10} row-gap={4}
			transition="fade slide-up(10)" background={selected() == n.id ? c("#ffffff", "#1d2232") : c("#00000000", "#00000000")}
			shadow={selected() == n.id ? (dark() ? "0 1px 0 rgba(0,0,0,0.4)" : "0 1px 3px rgba(20,30,60,0.12)") : "none"} onPress={() -> selected(n.id)}>
			<view direction="row" align-items="center" column-gap={6}>
				<Show when={n.pinned}><view width={6} height={6} radius={3} background="#f59e0b" transition="pop"/></Show>
				<text grow={1} font-size={15} font-weight={600} text-overflow="ellipsis" text-wrap="nowrap">{n.title() == "" ? "Untitled" : n.title()}</text>
				<text font-size={12} shrink={0} text-wrap="nowrap" color={c("#8b90a0", "#7d849c")}>{ago(n.edited())}</text>
			</view>
			<text font-size={13} color={c("#6b7080", "#8f97b3")} max-lines={2} line-height={1.4}>{n.body() == "" ? "No text yet" : n.body().split("\n").join(" ")}</text>
		</view>;
	}

	static function Editor(props:{note:Note}):View {
		var n = props.note;
		return <view grow={1} padding="34 48" row-gap={14}>
			<view direction="row" align-items="center" column-gap={10}>
				<text font-size={13} color={c("#8b90a0", "#7d849c")}>{n.folder + " · edited " + ago(n.edited()) + (n.edited() > 0 ? " ago" : "") + " · " + words(n.body()) + " words"}</text>
				<view grow={1}/>
				<view tag="pin" role="button" focusable cursor="pointer" padding="5 12" radius={999} background={n.pinned() ? "#fef3c7" : c("#eef0f5", "#232838")}
					onPress={togglePin}>
					<text font-size={13} font-weight={600} color={n.pinned() ? "#b45309" : c("#6b7080", "#8f97b3")}>{n.pinned() ? "Pinned" : "Pin"}</text>
				</view>
			</view>
			<field tag="title" value={n.title} label="Title" font-family="Inter" font-size={32} font-weight={700} letter-spacing={-0.6} padding={0}
				background="#00000000" border-width={0} color={c("#14161d", "#eef1fb")} onInput={e -> n.title(e.text)}/>
			<field:textarea tag="body" grow={1} value={n.body} label="Note" font-size={16} line-height={1.65} padding={0} background="#00000000" border-width={0}
				color={c("#2c3040", "#c9cfe2")} onInput={e -> n.body(e.text)}/>
		</view>;
	}

	static function Keycap(props:{label:String}):View
		return <view padding="2 7" radius={5} shrink={0} background={c("#eef0f5", "#232838")} border-width={1} border-color={c("#dde0e8", "#2e3448")}>
			<text font-size={11} font-weight={600} text-wrap="nowrap" color={c("#6b7080", "#8f97b3")}>{props.label}</text>
		</view>;

	static function Result(props:{c:Read<Command>}):View {
		var i = () -> found().indexOf(props.c());
		return <view tag={"result-" + untrack(i)} direction="row" align-items="center" column-gap={12} padding="10 14" radius={10} cursor="pointer"
			onClick={() -> run(i())} onPointerEnter={_ -> pick(i())}>
			<Show when={() -> pick() == i()}>
				<view matched="pick" position="absolute" left={0} top={0} right={0} bottom={0} radius={10} background={c("#eef1ff", "#252c46")}/>
			</Show>
			<view width={8} height={8} radius={4} background={props.c().kind == "Command" ? "#6d8bff" : props.c().kind == "Folder" ? "#22c55e" : "#f59e0b"}/>
			<text grow={1} font-size={15} font-weight={pick() == i() ? 600 : 450}>{props.c().label}</text>
			<text font-size={12} color={c("#8b90a0", "#7d849c")}>{props.c().kind}</text>
			<Show when={() -> props.c().keys != ""}><Keycap label={props.c().keys}/></Show>
		</view>;
	}

	static function Launcher():View {
		var input:Null<helder.ui.Node> = null;
		onSettled(() -> if (input != null) input.focus());
		return <view position="absolute" left={0} top={0} right={0} bottom={0} z-index={10} align-items="center" padding="110 0 0 0" transition="fade"
			background={dark() ? "#00000088" : "#1a1f3355"} onClick={() -> closeLauncher()}>
			<view tag="launcher" width={620} radius={16} background={c("#ffffff", "#141824")} border-width={1} border-color={c("#e3e6ee", "#2a3048")}
				shadow="0 30px 80px rgba(10, 15, 40, 0.35)" transition="fade scale" onClick={e -> e.stop()}>
				<view direction="row" align-items="center" column-gap={10} padding="14 18" border-width="0 0 1 0" border-color={c("#eceef3", "#232838")}>
					<icon name="search" width={18} height={18} color={c("#8b90a0", "#7d849c")}/>
					<field tag="query" grow={1} value={query} placeholder="Type a command or a note's name" label="Command" font-size={17} padding={0}
						background="#00000000" border-width={0} ref={n -> input = n} onInput={e -> {
							query(e.text);
							pick(0);
						}} onKeyDown={e -> switch e.key {
							case Key.DOWN:
								pick(Std.int(Math.min(found().length - 1, pick() + 1)));
								e.preventDefault();
							case Key.UP:
								pick(Std.int(Math.max(0, pick() - 1)));
								e.preventDefault();
							case Key.ENTER:
								run(pick());
								e.preventDefault();
							case Key.ESCAPE:
								closeLauncher();
								e.preventDefault();
							case _:
						}}/>
					<Keycap label="esc"/>
				</view>
				<view padding={8} row-gap={2} motion="snappy">
					<For each={found} by={x -> x.label}>{(x:Read<Command>) -> <Result c={x}/>}</For>
					<Show when={() -> found().length == 0}><text padding={14} font-size={14} color={c("#8b90a0", "#7d849c")}>Nothing matches</text></Show>
				</view>
				<view direction="row" column-gap={16} padding="10 18" border-width="1 0 0 0" border-color={c("#eceef3", "#232838")}>
					<text font-size={12} color={c("#8b90a0", "#7d849c")}>↑ ↓ to move</text>
					<text font-size={12} color={c("#8b90a0", "#7d849c")}>↩ to run</text>
					<text font-size={12} color={c("#8b90a0", "#7d849c")}>esc to close</text>
				</view>
			</view>
		</view>;
	}

	static function key(e:helder.ui.Event) {
		var mod = e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0;
		if (mod) {
			switch e.key {
				case 0x6b:
					launcher() ? closeLauncher() : openLauncher();
				case 0x6e:
					newNote();
				case 0x70:
					togglePin();
				case 0x64:
					dark(!dark());
				case _:
					return;
			}
			e.preventDefault();
			return;
		}
		if (e.mods & Key.MOD_ALT != 0 && (e.key == Key.UP || e.key == Key.DOWN)) {
			step(e.key == Key.UP ? -1 : 1);
			e.preventDefault();
		}
	}

	public static function view():View
		return <view tag="app" focusable ref={n -> app = n} grow={1} direction="row" font-family="Inter" motion="default" motion-color="calm" background={c("#f6f7fa", "#0d1018")}
			color={c("#14161d", "#eef1fb")} onKeyDown={key}>
			<view width={232} padding="22 14" row-gap={4} background={c("#eef0f5", "#11141e")} border-width="0 1 0 0" border-color={c("#e3e6ee", "#1e2333")}>
				<view direction="row" align-items="center" column-gap={10} padding="0 8 14 8">
					<view width={26} height={26} radius={8} background="linear-gradient(135deg, #f59e0b, #ef4444)"/>
					<text font-size={17} font-weight={700}>Notes</text>
				</view>
				<view tag="open-launcher" role="button" focusable cursor="pointer" direction="row" align-items="center" column-gap={8} padding="8 10" radius={8}
					margin="0 0 12 0" background={c("#ffffff", "#1a1f2d")} border-width={1} border-color={c("#e3e6ee", "#262c3e")} onPress={openLauncher}>
					<icon name="search" width={14} height={14} color={c("#8b90a0", "#7d849c")}/>
					<text grow={1} font-size={13} text-wrap="nowrap" color={c("#8b90a0", "#7d849c")}>Search…</text>
					<Keycap label="Ctrl K"/>
				</view>
				<Repeat count={FOLDERS.length}>{k -> <Folder name={FOLDERS[k]}/>}</Repeat>
				<view grow={1}/>
				<view tag="theme" role="button" focusable cursor="pointer" padding="8 12" radius={8} onPress={() -> dark(!dark())}>
					<text font-size={13} color={c("#6b7080", "#8f97b3")}>{dark() ? "Light theme" : "Dark theme"}</text>
				</view>
			</view>
			<view width={330} padding="22 12" row-gap={6} border-width="0 1 0 0" border-color={c("#e3e6ee", "#1e2333")}>
				<view direction="row" align-items="center" padding="0 6 10 6">
					<text grow={1} font-size={19} font-weight={700} letter-spacing={-0.3}>{folder()}</text>
					<view tag="new" role="button" focusable cursor="pointer" padding="5 12" radius={8} background="#14161d" onPress={newNote}>
						<text font-size={13} font-weight={600} color="#ffffff">New</text>
					</view>
				</view>
				<view tag="list" role="listbox" label="Notes" row-gap={4}>
					<For each={shown}>{(n:Read<Note>) -> <Item note={untrack(() -> n())}/>}</For>
				</view>
			</view>
			<view grow={1} min-width={0}>
				<For each={() -> {
					var n = current();
					n == null ? [] : [n];
				}}>{(n:Read<Note>) -> <view position="absolute" left={0} top={0} right={0} bottom={0} transition="fade"><Editor note={untrack(() -> n())}/></view>}</For>
			</view>
			<Show when={launcher}>{() -> Launcher()}</Show>
		</view>;

	static function main() {
		try helder.text.SystemFonts.get().add(helder.asset.Asset.embed("fonts/Inter.ttf")) catch (_:Dynamic) {}
		var focused = false;
		helder.ui.Clock.add(_ -> {
			if (!focused && app != null && app.ui != null) {
				focused = true;
				app.focus(false);
			}
			!focused;
		});
		UiWindow.run(<Surface title="Notes" width={1280} height={720}>{view()}</Surface>);
	}
}
