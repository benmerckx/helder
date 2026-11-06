package helder.os.wayland;

import helder.test.Test;

// Wayland's text-input-unstable-v3 client (WaylandTextInput) without a
// compositor: Proxy.recorder takes its requests, the test is the
// compositor and its input method (events delivered to the listener): the
// surface entered, text input enabled with the field's state (enable, the
// surrounding text in UTF-8 bytes, the content type, the caret's
// rectangle, commit), its changes committed, a password's text not sent;
// the input method's double-buffered events applied at done in the
// protocol's order (a preedit as TextEditing, its caret in UTF-16; a
// commit ending it and typed; delete_surrounding_text as TextReplace of the
// field's text, after the selection then before it; a leave ending the
// composition); a long text sent as a window around the caret; disabled
// when text input stops.
function tests() {
	describe("Wayland text-input-v3", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (hxmc.unsafe.Mem.os() == 0 && hxmc.unsafe.Mem.target() < 9) {
		// (the requests' opcodes: destroy, enable, disable, set_surrounding_text,
		// set_text_change_cause, set_content_type, set_cursor_rectangle, commit)
		final NAMES = ["destroy", "enable", "disable", "surrounding", "cause", "content", "rect", "commit"];
		final SIGS = ["", "", "", "sii", "u", "uu", "iiii", ""];
		var seen:Array<String> = [];
		var events:Array<String> = [];
		var surface = hxmc.unsafe.Ptr.ofI64(0x2000);
		function make():WaylandTextInput {
			Proxy.recorder = (proxy, opcode, iface, version, flags, args, count) -> {
				var sig = SIGS[opcode], a = [];
				for (k in 0...count)
					a.push(sig.charAt(k) == "s" ? Proxy.string(args, k) ?? "null" : Std.string(Proxy.int(args, k)));
				seen.push(NAMES[opcode] + (a.length > 0 ? " " + a.join(",") : ""));
				return hxmc.unsafe.Ptr.nil();
			};
			return new WaylandTextInput(hxmc.unsafe.Ptr.ofI64(0x9000), (kind, text, x, y) -> events.push(switch kind {
				case TextInput: "input " + text;
				case TextEditing: 'editing $text $x';
				case TextReplace: 'replace $x-$y $text';
				case _: "?";
			}));
		}
		function deliver(t:WaylandTextInput, opcode:Int, ?s:String, a = 0, b = 0)
			hxmc.unsafe.Arena.scoped(m -> {
				var args:hxmc.unsafe.Ptr<hxmc.unsafe.Int64> = cast m.alloc(32);
				switch opcode {
					case 0 | 1: args[0] = surface.toI64();
					case 2:
						Proxy.setString(m, args, 0, s);
						args[1] = a;
						args[2] = b;
					case 3: Proxy.setString(m, args, 0, s);
					case 4 | 5:
						args[0] = a;
						args[1] = b;
				}
				Proxy.deliver(t.slot, opcode, args);
			});
		function took():String {
			var s = seen.join(" | ");
			seen.resize(0);
			return s;
		}
		function told():String {
			var s = events.join(" | ");
			events.resize(0);
			return s;
		}
		afterEach(() -> {
			Proxy.recorder = null;
			seen.resize(0);
			events.resize(0);
		});
		test("enabled where entered, with the field's state; its changes committed", () -> {
			var t = make();
			t.begin(surface, 10, 20, 1, 16);
			equals(took(), "", "not entered yet: nothing");
			deliver(t, 0);
			assert(t.enabled);
			equals(took(), "enable | content 0,0 | rect 10,20,1,16 | commit");
			// (é is two bytes: the caret after "hé" at byte 3)
			t.context("héllo", 2, 2, false, false);
			equals(took(), "surrounding héllo,3,3 | content 0,0 | commit");
			t.context("a\nb", 0, 3, true, false);
			equals(took(), "surrounding a\nb,3,0 | content 512,0 | commit");
			t.begin(surface, 12, 20, 1, 16);
			equals(took(), "rect 12,20,1,16 | commit");
			t.context("secret", 6, 6, false, true);
			equals(took(), "content 192,8 | commit", "a password: no text, its content type");
			equals(t.commits, 5);
			t.stop();
			equals(took(), "disable | commit");
			Proxy.forget(t.slot);
		});
		test("a composition, its commit, the text around deleted", () -> {
			var t = make();
			t.begin(surface, 0, 0, 1, 16);
			deliver(t, 0);
			t.context("abc def", 3, 3, false, false);
			took();
			// (the preedit's caret at byte 3: after "に", one UTF-16 unit)
			deliver(t, 2, "にほ", 3, 3);
			deliver(t, 5, null, 2);
			equals(told(), "editing にほ 1");
			deliver(t, 2, "にほん", 9, 9);
			deliver(t, 5, null, 3);
			equals(told(), "editing にほん 3");
			deliver(t, 3, "日本");
			deliver(t, 5, null, 4);
			equals(told(), "editing  0 | input 日本", "committed: the composition gone, then typed");
			// (the field's text now "abc日本 def", the caret after 日本: one byte after, three bytes (本) before)
			t.context("abc日本 def", 5, 5, false, false);
			took();
			deliver(t, 4, null, 3, 1);
			deliver(t, 3, "X");
			deliver(t, 5, null, 5);
			equals(told(), "replace 5-6  | replace 4-5  | input X");
			// (a leave ends a composition)
			deliver(t, 2, "か", 3, 3);
			deliver(t, 5, null, 6);
			told();
			deliver(t, 1);
			assert(!t.enabled);
			equals(told(), "editing  0");
			Proxy.forget(t.slot);
		});
		test("a long text: a window around the caret, at most 4000 bytes", () -> {
			var t = make();
			var long = StringTools.lpad("", "é", 3000) + "|" + StringTools.lpad("", "x", 3000);
			t.begin(surface, 0, 0, 1, 16);
			deliver(t, 0);
			took();
			t.context(long, 3000, 3000, false, false);
			var s = seen[0];
			var parts = s.substr("surrounding ".length).split(",");
			var text = parts.slice(0, parts.length - 2).join(",");
			assert(WaylandTextInput.bytes(text) <= 4000, "within 4000 bytes");
			var cursor = Std.parseInt(parts[parts.length - 2]);
			// (the caret at the "|": the bytes before it in the window)
			equals(text.charAt(WaylandTextInput.unitsOf(text, cursor)), "|");
			Proxy.forget(t.slot);
		});
		}
		#end
		test("UTF-8 lengths and UTF-16 units", () -> {
			equals(WaylandTextInput.bytes("aé日😀"), 1 + 2 + 3 + 4);
			equals(WaylandTextInput.unitsOf("aé日😀b", 6), 3);
			equals(WaylandTextInput.unitsOf("aé日😀b", 10), 5);
		});
	});
}
