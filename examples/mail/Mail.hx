// title: Mail
// summary: A mail client's three panes: folders, messages sorted by a click on a column's title, the one selected read beside them; a toolbar, shortcuts, search and undo
// tags: ui, view, styles
// demo: canvas 860x560
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.ui.view.UiFlow.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import helder.view.graph.Read;

// A mail client's window on helder.ui (no network: the messages are made
// here), of plain views: the folders (each with its unread count, the
// subfolders indented), the folder's messages in columns (sorted by a click
// on a column's title, unread ones in bold, filtered by the search field;
// Up and Down move the selection), the selected message read in the third
// pane (which marks it read). The toolbar archives, deletes (a line at the
// bottom offers to undo) or marks it unread again, and switches dark mode;
// the same actions have shortcuts (Hotkey: E, Delete, Mod+Shift+U), from
// anywhere but the search field. Its look is Mail.sheet: rules by slot and
// state, colours with a light and a dark value (the window's Ui.dark, at
// first the system's). In a window:
//
//   haxe -lib helder -cp examples/mail -main Mail --custom-target hxmc=mail -D hxmc.libc=glibc
class Mail implements Markup {
	static function main() {
		UiWindow.run(<Surface title="Mail" width={860} height={560} theme={sheet}>{new Mail().view()}</Surface>);
	}

	public final folders:Array<Folder> = [
		{name: "Inbox", level: 0},
		{name: "Receipts", level: 1},
		{name: "Travel", level: 1},
		{name: "Sent", level: 0},
		{name: "Archive", level: 0},
		{name: "Trash", level: 0}
	];
	public final messages = signal(new Array<Message>());
	public final folder:Signal<Folder>;
	public final selected:Signal<Null<Message>> = signal(null);
	public final query = signal("");
	// the column sorted by ("from", "subject", "date") and whether descending
	public final sort = signal({by: "date", down: true});
	// the last move, while it can be undone
	public final undo:Signal<Null<{text:String, run:Void->Void}>> = signal(null);
	public final dark = signal(UiWindow.dark.peek());
	var root:Null<Node> = null;

	public function new() {
		folder = signal(folders[0]);
		var list = [];
		for (m in MESSAGES)
			list.push(new Message(m[0], m[1], m[2], m[3], Std.parseInt(m[4]), m[5] == "unread"));
		messages(list);
		// (a message read once it is shown)
		effect(() -> selected(), m -> if (m != null) m.unread(false));
		effect(() -> dark(), d -> if (root != null && root.ui != null) root.ui.dark = d);
	}

	// the folder's messages that the search matches, in the sorted column's order
	function shown():Array<Message> {
		var f = folder(), q = query().toLowerCase(), s = sort();
		var list = [
			for (m in messages())
				if (m.folder() == f.name && (q == "" || m.subject.toLowerCase().indexOf(q) >= 0 || m.from.toLowerCase().indexOf(q) >= 0))
					m
		];
		list.sort((a, b) -> {
			var c = switch s.by {
				case "from": Reflect.compare(a.from, b.from);
				case "subject": Reflect.compare(a.subject, b.subject);
				case _: a.day - b.day;
			}
			return s.down ? -c : c;
		});
		return list;
	}

	function unread(f:Folder):Int {
		var n = 0;
		for (m in messages())
			if (m.folder() == f.name && m.unread()) n++;
		return n;
	}

	// the selected message to another folder (the selection moving to the next one), undone from the line at the bottom
	function moveTo(name:String) {
		var m = selected.peek();
		if (m == null) return;
		var list = untrack(shown), i = list.indexOf(m), from = m.folder.peek();
		// (the move landed first: the list read again after it)
		flush(() -> {
			m.folder(name);
			messages(messages.peek().copy());
		});
		var rest = untrack(shown);
		selected(rest.length == 0 ? null : rest[i < rest.length ? i : rest.length - 1]);
		undo({
			text: 'Moved "${m.subject}" to $name',
			run: () -> {
				m.folder(from);
				messages(messages.peek().copy());
				selected(m);
				undo(null);
			}
		});
	}

	function markUnread() {
		var m = selected.peek();
		if (m == null) return;
		m.unread(true);
		// (deselected, or showing it would read it again)
		selected(null);
	}

	// Up and Down in the list: the selection to the message before or after
	function step(d:Int) {
		var list = untrack(shown);
		if (list.length == 0) return;
		var i = list.indexOf(selected.peek()) + d;
		selected(list[i < 0 ? 0 : i >= list.length ? list.length - 1 : i]);
	}

	function sortBy(by:String) {
		var s = sort.peek();
		sort({by: by, down: s.by == by ? !s.down : by == "date"});
	}

	static function Button(props:{label:String, onClick:Void->Void, ?tag:String, ?variant:String}):View
		return <view:button tag={props.tag ?? "button"} slot="button" variant={props.variant} role="button" focusable
			onPress={props.onClick}>{props.label}</view:button>;

	// a column's title: sorts by it, an arrow where it is sorted
	function Column(props:{title:String, by:String, ?width:Float}):View
		return <view:button tag={"sort-" + props.by} slot="column" role="button" focusable width={props.width} grow={props.width == null ? 1 : 0}
			onPress={() -> sortBy(props.by)}>
			{props.title + (sort().by == props.by ? (sort().down ? " ↓" : " ↑") : "")}
		</view:button>;

	// a message's cell: bold while it is unread, cut with an ellipsis
	function cell(m:Message, text:String, ?width:Float):View
		return <text width={width} grow={width == null ? 1 : 0} min-width={0} shrink={width == null ? 1 : 0} font-weight={m.unread() ? 700 : 400}
			text-wrap="nowrap" text-overflow="ellipsis">{text}</text>;

	public function view():View
		return <view slot="body" ref={n -> root = n} grow={1} font-family="DejaVu Sans" font-size={13}>
			<Hotkey keys="E" action={() -> moveTo("Archive")}/>
			<Hotkey keys="Delete" action={() -> moveTo("Trash")}/>
			<Hotkey keys="Mod+Shift+U" action={markUnread}/>
			<view slot="bar" direction="row" align-items="center" column-gap={8} padding="8 12">
				<text font-weight={700} font-size={15} padding="0 8 0 0">Mail</text>
				<Button tag="archive" label="Archive" onClick={() -> moveTo("Archive")}/>
				<Button tag="delete" label="Delete" onClick={() -> moveTo("Trash")}/>
				<Button tag="unread" label="Mark unread" onClick={markUnread}/>
				<view grow={1}/>
				<Button tag="dark" label="Dark mode" variant="ghost" onClick={() -> dark(!dark.peek())}/>
				<field tag="search" slot="input" width={200} value={query} placeholder="Search" label="Search messages" onInput={e -> query(e.text)}/>
			</view>
			<view direction="row" grow={1} min-height={0} column-gap={12} padding={12}>
				<view tag="folders" width={170} shrink={0} row-gap={2} role="list" label="Folders">
					<For each={folders}>{(folderOf:Read<Folder>) -> {
						var f = folderOf();
						<view:button slot="folder" role="listitem" focusable selected={folder() == f} data-state={folder() == f ? "selected" : null}
							padding={[5, 8, 5, 8 + 16 * f.level]} onPress={() -> {
								folder(f);
								selected(null);
							}}>
							<text grow={1}>{f.name}</text>
							<text slot="muted">{count(unread(f))}</text>
						</view:button>;
					}}</For>
				</view>
				<view slot="panel" width={340} shrink={0} min-height={0}>
					<view slot="head" direction="row" column-gap={8}>
						<Column title="From" by="from" width={90}/>
						<Column title="Subject" by="subject"/>
						<Column title="Date" by="date" width={52}/>
					</view>
					<scroll tag="list" grow={1} min-height={0} focusable role="list" label="Messages" onKeyDown={e -> switch e.key {
						case Key.DOWN:
							step(1);
							e.preventDefault();
						case Key.UP:
							step(-1);
							e.preventDefault();
						case _:
					}}>
						<For each={shown()}>{(message:Read<Message>) -> {
							var m = message();
							<view slot="row" role="listitem" direction="row" column-gap={8} selected={selected() == m}
								data-state={selected() == m ? "selected" : null} onClick={() -> selected(m)}>
								{cell(m, m.from, 90)}{cell(m, m.subject)}{cell(m, "Oct " + m.day, 52)}
							</view>;
						}}</For>
						<Show when={shown().length == 0}><text slot="muted" padding={12}>No messages</text></Show>
					</scroll>
				</view>
				<view tag="reader" slot="panel" grow={1} min-width={0} padding={16} row-gap={10}>
					<Show when={selected() != null} fallback={<text slot="muted">No message selected</text>}>
						<text tag="reader-subject" font-size={16} font-weight={600}>{selected()?.subject}</text>
						<text slot="muted">{selected() == null ? "" : "From " + selected().from + ", October " + selected().day}</text>
						<view slot="rule" height={1}/>
						<text tag="reader-body" line-height={1.5}>{selected()?.body}</text>
					</Show>
				</view>
			</view>
			<Show when={undo() != null}>
				<view slot="bar" direction="row" align-items="center" column-gap={12} padding="6 12" live="polite">
					<text grow={1}>{undo()?.text}</text>
					<Button tag="undo" label="Undo" variant="ghost" onClick={() -> undo.peek()?.run()}/>
					<Button tag="dismiss" label="×" variant="ghost" onClick={() -> undo(null)}/>
				</view>
			</Show>
		</view>;

	static function count(n:Int):String
		return n == 0 ? "" : Std.string(n);

	static inline function token(name:String):Color
		return Color.parse('var(--$name)');

	public static final sheet:StyleSheet = {
		rules: [
			{slot: "body", style: {background: token("background"), color: token("foreground")}},
			{slot: "bar", style: {background: token("muted-background")}},
			{slot: "muted", style: {color: token("muted")}},
			{slot: "rule", style: {background: token("border")}},
			{slot: "panel", style: {radius: 8, borderWidth: 1, borderColor: token("border"), background: token("card")}},
			{slot: "head", style: {padding: [6, 10], borders: [0, 0, 1, 0], borderColor: token("border")}},
			{slot: "column", style: {direction: Row, color: token("muted"), fontWeight: 600, cursor: Pointer}},
			{slot: "column", when: ["hover"], style: {color: token("foreground")}},
			{slot: "row", style: {padding: [5, 10], cursor: Pointer}},
			{slot: "row", when: ["hover"], style: {background: token("hover")}},
			{slot: "row", when: ["data-state=selected"], style: {background: token("accent"), color: token("accent-foreground")}},
			{slot: "folder", style: {direction: Row, alignItems: Center, radius: 6, cursor: Pointer}},
			{slot: "folder", when: ["hover"], style: {background: token("hover")}},
			{slot: "folder", when: ["data-state=selected"], style: {background: token("accent"), color: token("accent-foreground"), fontWeight: 600}},
			{slot: "button", style: {direction: Row, alignItems: Center, padding: [5, 10], radius: 6, borderWidth: 1, borderColor: token("border"),
				background: token("card"), cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {background: token("hover")}},
			{slot: "button", variant: "ghost", style: {borderColor: Color.TRANSPARENT, background: Color.TRANSPARENT}},
			{slot: "button", variant: "ghost", when: ["hover"], style: {background: token("hover")}},
			{slot: "input", style: {padding: [5, 10], radius: 6, borderWidth: 1, borderColor: token("border"), background: token("card")}},
			{slot: "input", when: ["focus"], style: {borderColor: token("muted")}},
			{slot: "input", when: ["placeholder"], style: {color: token("muted")}}
		],
		light: [
			"background" => Color.rgb(0xFFFFFF), "foreground" => Color.rgb(0x18181B), "muted-background" => Color.rgb(0xF4F4F5), "muted" => Color.rgb(0x71717A),
			"border" => Color.rgb(0xE4E4E7), "card" => Color.rgb(0xFFFFFF), "hover" => Color.rgb(0xF4F4F5), "accent" => Color.rgb(0xDBEAFE),
			"accent-foreground" => Color.rgb(0x1E3A8A)
		],
		dark: [
			"background" => Color.rgb(0x09090B), "foreground" => Color.rgb(0xFAFAFA), "muted-background" => Color.rgb(0x18181B), "muted" => Color.rgb(0xA1A1AA),
			"border" => Color.rgb(0x27272A), "card" => Color.rgb(0x09090B), "hover" => Color.rgb(0x27272A), "accent" => Color.rgb(0x1E3A8A),
			"accent-foreground" => Color.rgb(0xDBEAFE)
		]
	};

	// from, subject, body, folder, day of October, read or unread
	static final MESSAGES = [
		["Ada", "Draft of the layout chapter", "Here is the chapter on flexbox and grid. The figures are still placeholders; tell me which ones you want redrawn.", "Inbox", "17", "unread"],
		["Grace", "Compiler meeting moved", "The meeting moves to Thursday at ten, same room. Bring the benchmark numbers for the WasmGC build if you have them.", "Inbox", "17", "unread"],
		["Linus", "Re: patch for the scheduler", "Looks fine to me. One nit: the comment above the loop no longer says what it does.", "Inbox", "16", "read"],
		["Margaret", "Launch checklist", "Attached is the checklist for Monday. Every item needs an owner by Friday.", "Inbox", "15", "unread"],
		["Alan", "Lunch?", "There is a new place near the station. Tuesday works for me.", "Inbox", "14", "read"],
		["Barbara", "Notes from the review", "The review went well. The main question was about error messages: they should point at the line that caused them.", "Inbox", "13", "read"],
		["Ken", "Old terminal manuals", "I found a box of manuals from the lab. Do you want any of them before they go to the recycling?", "Inbox", "11", "read"],
		["Bookshop", "Your order has shipped", "Order 4417: two books, shipped today. Expected on Tuesday.", "Receipts", "12", "unread"],
		["Rail", "Your ticket for Brussels", "Coach 6, seat 41. The train leaves at 08:12 from platform 3.", "Travel", "10", "read"],
		["Hotel", "Booking confirmed", "Two nights from the 23rd. Breakfast is included.", "Travel", "9", "read"],
		["Ada", "Re: figures", "I can redraw the grid figures this week.", "Sent", "16", "read"],
		["Dennis", "Release notes", "The notes for the release are in the usual place.", "Archive", "2", "read"]
	];
}

typedef Folder = {name:String, level:Int};

class Message {
	public final from:String;
	public final subject:String;
	public final body:String;
	public final day:Int;
	public final folder:Signal<String>;
	public final unread:Signal<Bool>;

	public function new(from:String, subject:String, body:String, folder:String, day:Int, unread:Bool) {
		this.from = from;
		this.subject = subject;
		this.body = body;
		this.day = day;
		this.folder = signal(folder);
		this.unread = signal(unread);
	}
}
