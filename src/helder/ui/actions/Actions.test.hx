package helder.ui.actions;

import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Popup;
import helder.ui.Ui;
import helder.ui.actions.Actions;
import helder.ui.actions.ContextPredicate;

// helder.ui.actions: dispatch from the focus up to the window and the app,
// context predicates and their depth, keystrokes and chords (with their
// timeout), conflicts, a user's JSON overriding the defaults, the keys an
// action is bound to, Tab's order and the focus given back by a popup, and
// markup's key-context, actions and track-focus
function tests() {
	actions("test", TestAction);
	describe("Context predicates", () -> {
		var stack = [KeyContext.parse("Workspace"), KeyContext.parse("Pane"), KeyContext.parse("Editor mode=full read_only")];
		test("identifiers, values, not, and, or, the deepest prefix", () -> {
			equals(Predicates.depth(Predicates.parse("Editor"), stack), 3);
			equals(Predicates.depth(Predicates.parse("Pane"), stack), 2);
			equals(Predicates.depth(Predicates.parse("Editor && !read_only"), stack), 0);
			equals(Predicates.depth(Predicates.parse("Editor && read_only"), stack), 3);
			equals(Predicates.depth(Predicates.parse("mode == full"), stack), 3);
			equals(Predicates.depth(Predicates.parse("mode != full"), stack), 2);
			equals(Predicates.depth(Predicates.parse("Picker || Workspace"), stack), 1);
			equals(Predicates.depth(Predicates.parse("!(Picker)"), stack), 3);
		});
		test("descendant: a > b", () -> {
			equals(Predicates.depth(Predicates.parse("Workspace > Editor"), stack), 3);
			equals(Predicates.depth(Predicates.parse("Picker > Editor"), stack), 0);
			equals(Predicates.depth(Predicates.parse("Workspace > Pane"), stack), 2);
		});
		test("bad predicates are errors", () -> {
			throws(() -> Predicates.parse("Editor &&"));
			throws(() -> Predicates.parse("(Editor"));
		});
	});

	describe("Keystrokes", () -> {
		test("parsed as GPUI writes them, secondary per platform", () -> {
			var k = Keystroke.parse("ctrl-shift-s");
			equals(k.key, "s".code);
			equals(k.mods, Key.MOD_CONTROL | Key.MOD_SHIFT);
			assert(k.matches("S".code, Key.MOD_CONTROL | Key.MOD_SHIFT));
			assert(!k.matches("s".code, Key.MOD_CONTROL));
			equals(Keystroke.parse("ctrl--").key, "-".code);
			equals(Keystroke.parse("-").key, "-".code);
			equals(Keystroke.parse("f11").key, Key.F1 + 10);
			equals(Keystroke.sequence("secondary-k secondary-s").length, 2);
			Keymap.mac = true;
			assert(Keystroke.parse("secondary-o").matches("o".code, Key.MOD_META));
			assert(!Keystroke.parse("secondary-o").matches("o".code, Key.MOD_CONTROL));
			equals(Keystroke.parse("secondary-shift-o").label(), "⇧⌘O");
			Keymap.mac = false;
			assert(Keystroke.parse("secondary-o").matches("o".code, Key.MOD_CONTROL));
			equals(Keystroke.parse("secondary-shift-o").label(), "Ctrl+Shift+O");
			throws(() -> Keystroke.parse("hyper-x"));
		});
	});

	describe("Dispatch", () -> {
		test("from the focus up, the window, then the app; bubbling on false", () -> {
			var f = fixture(), log = [];
			f.leaf.on(TestAction, a -> {
				log.push("leaf " + Actions.name(a));
				a == Bubble ? false : true;
			});
			f.root.on(TestAction, a -> {
				log.push("root " + Actions.name(a));
				true;
			});
			f.ui.setFocus(f.leaf);
			assert(f.ui.dispatchAction(Bubble));
			assert(f.ui.dispatchAction(Next));
			equals(log, ["leaf test::Bubble", "root test::Bubble", "leaf test::Next"]);
			// (the window's, the app's, when the tree takes none)
			var other = new Ui(null, 100, 100), seen = [];
			var off1 = other.on(TestAction, a -> {
				seen.push("window");
				a.match(Zoom(1));
			});
			var off2 = Actions.on(TestAction, a -> {
				seen.push("app");
				true;
			});
			assert(other.dispatchAction(Zoom(1)));
			assert(other.dispatchAction(Next));
			equals(seen, ["window", "window", "app"]);
			off1();
			off2();
			assert(!other.dispatchAction(Next));
		});
		test("states: a disabled handler's action taken, not run; unhandled passed over", () -> {
			var f = fixture(), ran = 0;
			f.leaf.on(TestAction, a -> {
				ran++;
				true;
			}, a -> switch a {
				case Next: Disabled;
				case Zoom(_): Checked;
				case _: Unhandled;
			});
			f.ui.setFocus(f.leaf);
			equals(f.ui.actionState(Next), Disabled);
			equals(f.ui.actionState(Zoom(2)), Checked);
			equals(f.ui.actionState(Bubble), Unhandled);
			assert(f.ui.dispatchAction(Next));
			equals(ran, 0);
			assert(!f.ui.dispatchAction(Bubble));
		});
		test("a popup's focus dispatches on to its anchor's ancestors; the focus given back on close", () -> {
			var f = fixture(), log = [];
			f.root.on(TestAction, a -> {
				log.push("root");
				true;
			});
			f.ui.setFocus(f.leaf);
			var p = new Popup("menu");
			p.anchor = f.leaf;
			var item = new Node("item");
			item.focusable = true;
			p.append(item);
			f.ui.open(p);
			f.ui.setFocus(item);
			assert(f.ui.dispatchAction(Next));
			equals(log, ["root"]);
			equals(f.ui.contextStack().length, 3);
			f.ui.close(p);
			equals(f.ui.focus, f.leaf);
		});
		test("JSON names: parsed with arguments", () -> {
			equals(Actions.parse("test::Next"), Next);
			equals(Actions.parse(["test::Zoom", 2]), Zoom(2));
			equals(Actions.parse(["test::Zoom", [3]]), Zoom(3));
			throws(() -> Actions.parse("test::Nope"));
			throws(() -> Actions.parse("nope::Next"));
		});
	});

	describe("Keymaps", () -> {
		test("the deepest context wins, then the later binding", () -> {
			var f = fixture(), log = [];
			f.ui.keymap = new Keymap().bind("n", Next).bind("n", Bubble, "Editor").bind("n", Zoom(1), "Workspace").bind("x", Zoom(1))
				.bind("x", Zoom(2));
			f.root.on(TestAction, a -> {
				log.push(Actions.name(a) + Std.string(Type.enumParameters(a)));
				true;
			});
			f.ui.setFocus(f.leaf);
			f.ui.keyDown("n".code, 0);
			f.ui.keyDown("x".code, 0);
			equals(log, ["test::Bubble[]", "test::Zoom[2]"]);
			// (out of the editor: the workspace's)
			f.ui.setFocus(f.side);
			f.ui.keyDown("n".code, 0);
			equals(log[2], "test::Zoom[1]");
		});
		test("a binding whose action nobody takes is passed over; null unbinds", () -> {
			var f = fixture(), log = [];
			f.ui.keymap = new Keymap().bind("n", Next).bind("n", StandardAction.About, "Editor");
			f.leaf.on(TestAction, a -> {
				log.push(Actions.name(a));
				true;
			});
			f.ui.setFocus(f.leaf);
			f.ui.keyDown("n".code, 0);
			equals(log, ["test::Next"]);
			f.ui.keymap.bind("n", null, "Editor");
			f.ui.keyDown("n".code, 0);
			equals(log, ["test::Next"]);
		});
		test("chords: pending, completed, broken, timed out", () -> {
			var f = fixture(), log = [];
			f.ui.keymap = new Keymap().bind("ctrl-k ctrl-s", Next).bind("ctrl-k", Bubble).bind("ctrl-x ctrl-y", Zoom(1));
			f.leaf.on(TestAction, a -> {
				log.push(Actions.name(a));
				true;
			});
			f.ui.setFocus(f.leaf);
			f.ui.keyDown("k".code, Key.MOD_CONTROL);
			equals(f.ui.pendingKeys.length, 1);
			equals(log, []);
			f.ui.keyDown("s".code, Key.MOD_CONTROL);
			equals(log, ["test::Next"]);
			equals(f.ui.pendingKeys.length, 0);
			// (broken: another key, which is tried alone)
			f.ui.keyDown("x".code, Key.MOD_CONTROL);
			f.ui.keyDown("k".code, Key.MOD_CONTROL);
			equals(f.ui.pendingKeys.length, 1);
			// (timed out: ctrl-k's own binding runs)
			Clock.tick(100);
			Clock.tick(100.5);
			equals(log, ["test::Next"]);
			Clock.tick(101.1);
			equals(log, ["test::Next", "test::Bubble"]);
			equals(f.ui.pendingKeys.length, 0);
		});
		test("a user's JSON after the defaults: overriding, unbinding, labels", () -> {
			Keymap.mac = false;
			var k = new Keymap().bind("secondary-o", Next).bind("f11", Bubble).bind("1", Zoom(100), "Editor");
			equals(k.label(Next), "Ctrl+O");
			k.setUser('[{"bindings": {"secondary-k secondary-n": "test::Next", "f11": null}},
				{"context": "Editor && !read_only", "bindings": {"2": ["test::Zoom", 100]}}]');
			var stack = [KeyContext.parse("Editor")];
			equals([for (s in k.keysFor(Next)) [for (x in s) x.toString()].join(" ")], ["secondary-k secondary-n", "secondary-o"]);
			equals(k.keysFor(Bubble).length, 0);
			equals(k.label(Zoom(100), stack), "2");
			equals(k.label(Zoom(100), [KeyContext.parse("Editor read_only")]), "1");
			equals(k.label(Zoom(5)), null);
			throws(() -> k.setUser('[{"bindings": {"q": "test::Nope"}}]'));
		});
		#if sys
		test("the user's file read again when it changes", () -> {
			var path = "bin/keymap-test.json";
			try sys.FileSystem.createDirectory("bin") catch (_:Dynamic) {}
			sys.io.File.saveContent(path, '[{"bindings": {"q": "test::Next"}}]');
			var k = new Keymap();
			k.loadUser(path);
			equals(k.label(Next), "Q");
			assert(!k.poll());
			sys.io.File.saveContent(path, '[{"bindings": {"w": "test::Next", "e": "test::Bubble"}}]');
			assert(k.poll());
			equals(k.label(Next), "W");
			sys.io.File.saveContent(path, 'not json, longer than before');
			assert(k.poll());
			notEquals(k.error, null);
			equals(k.label(Next), "W");
			sys.FileSystem.deleteFile(path);
			assert(k.poll());
			equals(k.label(Next), null);
		});
		#end
		test("typing keys stay with a text field; Control and the rest do not", () -> {
			var f = fixture(), log = [];
			var field = new helder.ui.widgets.TextField();
			f.root.append(field);
			f.ui.keymap = new Keymap().bind("n", Next).bind("ctrl-n", Bubble);
			f.root.on(TestAction, a -> {
				log.push(Actions.name(a));
				true;
			});
			f.ui.setFocus(field);
			f.ui.keyDown("n".code, 0);
			f.ui.keyDown("n".code, Key.MOD_CONTROL);
			equals(log, ["test::Bubble"]);
		});
	});

	describe("Focus", () -> {
		test("Tab and Shift+Tab: tabIndex first, then tree order, below 0 passed over", () -> {
			var ui = new Ui(null, 100, 100), names = [];
			for (t in ["a", "b", "c", "d"]) {
				var n = new Node(t);
				n.focusable = true;
				ui.root.append(n);
			}
			ui.root.find("c").tabIndex = 1;
			ui.root.find("b").tabIndex = -1;
			for (_ in 0...4) {
				ui.keyDown(Key.TAB, 0);
				names.push(ui.focus.tag);
			}
			equals(names, ["c", "a", "d", "c"]);
			ui.keyDown(Key.TAB, Key.MOD_SHIFT);
			equals(ui.focus.tag, "d");
			ui.root.find("b").focus();
			ui.keyDown(Key.TAB, 0);
			equals(ui.focus.tag, "c");
		});
		test("handles: focused and within", () -> {
			var f = fixture();
			var outer = new FocusHandle(), inner = new FocusHandle();
			outer.track(f.editor);
			inner.track(f.leaf);
			inner.focus();
			assert(inner.isFocused());
			assert(outer.containsFocus());
			assert(!outer.isFocused());
			assert(f.editor.focusWithin());
			f.side.focus();
			assert(!inner.isFocused());
			assert(!outer.containsFocus());
		});
		test("markup: key-context, actions, track-focus, tab-index", () -> {
			var ui = new Ui(null, 200, 200), log = [], handle = new FocusHandle();
			var dispose = helder.view.Render.render(Fixture.view(log, handle), ui.root);
			ui.update();
			ui.keymap = new Keymap().bind("z", Zoom(7), "Viewer && !picker");
			handle.focus();
			equals(ui.focus.tag, "image");
			equals(ui.contextStack()[0].toString(), "Viewer");
			ui.keyDown("z".code, 0);
			equals(log, ["Zoom(7)"]);
			equals(ui.root.find("image").tabIndex, 2);
			dispose();
		});
	});
}

enum TestAction {
	Next;
	Bubble;
	Zoom(by:Float);
}

// Workspace > Pane > Editor > leaf, and a side node in the workspace
function fixture() {
	var ui = new Ui(null, 200, 200);
	var root = ui.root;
	root.keyContext = KeyContext.parse("Workspace");
	var pane = new Node("pane"), editor = new Node("editor"), leaf = new Node("leaf"), side = new Node("side");
	pane.keyContext = KeyContext.parse("Pane");
	editor.keyContext = KeyContext.parse("Editor");
	leaf.focusable = side.focusable = true;
	root.append(pane);
	root.append(side);
	pane.append(editor);
	editor.append(leaf);
	return {ui: ui, root: root, editor: editor, leaf: leaf, side: side};
}

private class Fixture implements helder.view.Markup {
	public static function view(log:Array<String>, handle:FocusHandle)
		return <view key-context="Viewer" actions={[Actions.handle(TestAction, a -> {
			log.push(Std.string(a));
			true;
		})]}>
			<view tag="image" track-focus={handle} tab-index={2} width={20} height={20}/>
		</view>;
}
