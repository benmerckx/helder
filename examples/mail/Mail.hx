// title: Mail
// summary: A mail client's three panes: folders in a tree, messages in a sortable table, the one selected read beside them; a menu bar, a toolbar, search and undo
// tags: ui, view, widgets
// demo: canvas 860x560
import helder.theme.Shadcn;
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.Reactive.*;
import helder.ui.widgets.Widgets.*;
import helder.ui.widgets.Toasts;

// A mail client's window on helder.ui (no network: the messages are made
// here): the folders in a Tree (each with its unread count), the folder's
// messages in a Table (sorted by a click on a column's title, unread ones
// in bold, filtered by the search field), the selected message read in
// the third pane (which marks it read). The toolbar archives, deletes (a
// toast offers to undo) or marks it unread again; the menu bar opens the
// same actions (their shortcuts: E, Delete, Mod+Shift+U, from anywhere but
// the search field) and switches dark mode (the window's Ui.dark, at
// first the system's). In a window:
//
//   haxe -lib helder -lib helder -cp examples -main Mail --custom-target hxmc=mail -D hxmc.libc=glibc
class Mail implements Markup {
	static function main() {
		var w = new UiWindow("Mail", 860, 560);
		w.ui.theme = Shadcn.sheet;
		Render.render(new Mail().view(), w.root);
		UiWindow.run();
	}

	public final folders:Array<Folder> = [
		{name: "Inbox", children: [{name: "Receipts"}, {name: "Travel"}]},
		{name: "Sent"},
		{name: "Archive"},
		{name: "Trash"}
	];
	public final messages = signal(new Array<Message>());
	public final folder:Signal<Null<Folder>>;
	public final open:Signal<Array<Folder>>;
	public final selected:Signal<Null<Message>> = signal(null);
	public final query = signal("");
	public final pane = signal(190.0);
	public final dark = signal(UiWindow.dark.peek());
	var root:Null<Node> = null;

	public function new() {
		folder = signal(folders[0]);
		open = signal([folders[0]]);
		var list = [];
		for (m in MESSAGES)
			list.push(new Message(m[0], m[1], m[2], m[3], Std.parseInt(m[4]), m[5] == "unread"));
		messages.value = list;
		// (a message read once it is shown)
		effect(() -> {
			var m = selected.value;
			if (m != null) untrack(() -> m.unread.value = false);
		});
		effect(() -> {
			var d = dark.value;
			if (root != null && root.ui != null) root.ui.dark = d;
		});
	}

	// the folder's messages that the search matches
	function shown():Array<Message> {
		var f = folder.value, q = query.value.toLowerCase();
		return [
			for (m in messages.value)
				if (f != null && m.folder.value == f.name
					&& (q == "" || m.subject.toLowerCase().indexOf(q) >= 0 || m.from.toLowerCase().indexOf(q) >= 0))
					m
		];
	}

	function unread(f:Folder):Int {
		var n = 0;
		for (m in messages.value)
			if (m.folder.value == f.name && m.unread.value) n++;
		return n;
	}

	// the selected message to another folder (the selection moving to the next one)
	function moveTo(name:String, ?undo:Bool) {
		var m = selected.peek();
		if (m == null) return;
		var list = shown(), i = list.indexOf(m), from = m.folder.peek();
		m.folder.value = name;
		messages.value = messages.peek().copy();
		var rest = shown();
		selected.value = rest.length == 0 ? null : rest[i < rest.length ? i : rest.length - 1];
		if (undo == true)
			Toasts.show('Moved "${m.subject}" to $name', {
				action: "Undo",
				onAction: () -> {
					m.folder.value = from;
					messages.value = messages.peek().copy();
					selected.value = m;
				}
			});
	}

	function markUnread() {
		var m = selected.peek();
		if (m == null) return;
		m.unread.value = true;
		// (deselected, or showing it would read it again)
		selected.value = null;
	}

	// a folder in the tree: its name, its unread count
	function folderRow(f:Folder):View
		return <view direction="row" grow={1} justify="space-between" padding="0 8 0 0">
			{f.name}
			<text opacity={0.7}>{() -> count(unread(f))}</text>
		</view>;

	static function count(n:Int):String
		return n == 0 ? "" : Std.string(n);

	// a message's cell: bold while it is unread, cut with an ellipsis
	function cell(m:Message, text:String):View
		return <text font-weight={() -> m.unread.value ? 700 : 400} text-wrap="nowrap" text-overflow="ellipsis">{text}</text>;

	public function view():View
		return <view slot="body" ref={n -> root = n} grow={1} font-family="DejaVu Sans" font-size={13}>
			<view direction="row" align-items="center" column-gap={12} padding="8 12">
				<Menubar tag="menus" label="Mail" menus={[
					{label: "Message", items: [
						{label: "Archive", onSelect: () -> moveTo("Archive", true), shortcut: "E"},
						{label: "Delete", onSelect: () -> moveTo("Trash", true), shortcut: "Delete"},
						{label: "Mark unread", onSelect: markUnread, shortcut: "Mod+Shift+U"}
					]},
					{label: "View", items: [{label: "Dark mode", onSelect: () -> dark.value = !dark.peek()}]}
				]}/>
				<Toolbar tag="actions" label="Message">
					<Button tag="archive" label="Archive" onClick={() -> moveTo("Archive", true)}/>
					<Button tag="delete" label="Delete" onClick={() -> moveTo("Trash", true)}/>
					<Button tag="unread" label="Mark unread" onClick={markUnread}/>
				</Toolbar>
				<view grow={1}/>
				<view width={200}><Input tag="search" value={query} placeholder="Search" label="Search messages"/></view>
			</view>
			<Separator/>
			<view grow={1} min-height={0} padding={12}>
				<Split tag="panes" size={pane} min={140} max={320} label="Folders"
					first={<Tree tag="folders" roots={folders} children={(f:Folder) -> f.children} expanded={open} selected={folder} label="Folders"
						height={480} rowHeight={26} text={(f:Folder) -> f.name}
						render={folderRow}/>}
					second={<view direction="row" column-gap={12} grow={1} min-width={0}>
						<view width={330} shrink={0}>
							<Table tag="list" rows={shown} selected={selected} height={480} rowHeight={26} label="Messages" columns={[
								{title: "From", width: "110px", cell: (m:Message) -> cell(m, m.from), compare: (a:Message, b:Message) -> Reflect.compare(a.from, b.from)},
								{title: "Subject", cell: (m:Message) -> cell(m, m.subject), compare: (a:Message, b:Message) -> Reflect.compare(a.subject, b.subject)},
								{title: "Date", width: "54px", cell: (m:Message) -> "Oct " + m.day, compare: (a:Message, b:Message) -> a.day - b.day}
							]}/>
						</view>
						<view grow={1} min-width={0}><Card tag="reader">
							<Show when={() -> selected.value != null} fallback={<text opacity={0.6}>No message selected</text>}>
								<CardHeader>
									<CardTitle tag="reader-subject">{() -> selected.value?.subject}</CardTitle>
									<CardDescription>{() -> selected.value == null ? "" : "From " + selected.value.from + ", October " + selected.value.day}</CardDescription>
								</CardHeader>
								<Separator/>
								<CardContent><text tag="reader-body" line-height={1.5}>{() -> selected.value?.body}</text></CardContent>
							</Show>
						</Card></view>
					</view>}/>
			</view>
			<Toaster/>
		</view>;

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

typedef Folder = {name:String, ?children:Array<Folder>};

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
