import hxmc.unsafe.*;

// AT-SPI's client side (libatspi, as Orca reads applications): finds an
// application on the desktop by its window's title and reads its whole
// tree as an accessibility inspector does (Accerciser's checks): each
// object's role and name, its children's parent and index, its states, its
// extents inside its frame's, each interface it lists answering. Then the
// roles and names asked for must be in it ("role:name", the role as
// AT-SPI names it). For AccessApp's fixture it goes on: a table's rows,
// columns, cells and headers, an item's place in its set, a text input's
// text by words and lines, its selection set, text inserted, a read-only
// field, a disclosure expanded through its action (the new child's
// ChildrenChanged event), a row selected through the table's Selection, a
// slider's value set, an object scrolled into view; the events those
// raise; last the Save button's action, which closes it.
//   AtspiProbe <title> [role:name ...]
class AtspiProbe {
	static var failed = 0;
	static var checks = 0;
	static final events:Array<String> = [];

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('AtspiProbe: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static final err:Ptr<Ptr> = LibC.malloc(8);

	static function str(p:Ptr):String
		return p.isNull() ? "" : (cast p : CString).toString();

	static function name(a:Ptr):String
		return str(Atspi.atspi_accessible_get_name(a, err));

	static function role(a:Ptr):String
		return str(Atspi.atspi_accessible_get_role_name(a, err));

	static function children(a:Ptr):Array<Ptr>
		return [for (i in 0...Atspi.atspi_accessible_get_child_count(a, err)) Atspi.atspi_accessible_get_child_at_index(a, i, err)];

	static function has(a:Ptr, state:Int):Bool {
		var s = Atspi.atspi_accessible_get_state_set(a);
		return Atspi.atspi_state_set_contains(s, state) != 0;
	}

	static function interfaces(a:Ptr):Array<String> {
		var arr:Ptr<Ptr> = Atspi.atspi_accessible_get_interfaces(a);
		if (arr.isNull()) return [];
		var data:Ptr<Ptr> = arr[0], n:Int = ((cast arr : Ptr).add(8) : Ptr<Int32>).value;
		return [for (i in 0...n) str(data[i])];
	}

	static function extents(a:Ptr):Array<Int> {
		var c = Atspi.atspi_accessible_get_component_iface(a);
		var r:Ptr<Int32> = c.isNull() ? Ptr.nil() : Atspi.atspi_component_get_extents(c, 0, err);
		return r.isNull() ? [] : [r[0], r[1], r[2], r[3]];
	}

	static function attribute(a:Ptr, key:String):String {
		var attrs = Atspi.atspi_accessible_get_attributes(a, err);
		var v = attrs.isNull() ? Ptr.nil() : Arena.scopedValue(m -> GLib.g_hash_table_lookup(attrs, m.cstring(key)));
		return str(v);
	}

	// (libatspi's signals and replies: GLib's loop turned for a while)
	static function pump(seconds:Float) {
		var until = haxe.Timer.stamp() + seconds;
		while (haxe.Timer.stamp() < until) {
			while (GLib.g_main_context_iteration(Ptr.nil(), 0) != 0) {}
			Sys.sleep(0.02);
		}
	}

	@:hxmc.callback static function onEvent(e:Ptr):Void {
		var type = str((e : Ptr<Ptr>).value), source:Ptr = (e.add(8) : Ptr<Ptr>).value;
		events.push(type + "@" + (source.isNull() ? "" : name(source)));
	}

	static function saw(prefix:String, ?source:String):Bool {
		for (e in events)
			if (StringTools.startsWith(e, prefix) && (source == null || StringTools.endsWith(e, "@" + source))) return true;
		return false;
	}

	// every object under top, depth first: [object, depth]
	static function walk(top:Ptr, ?parent:Ptr, ?index:Int, depth = 0, ?out:Array<{o:Ptr, depth:Int}>, ?frame:Array<Int>):Array<{o:Ptr, depth:Int}> {
		if (out == null) out = [];
		out.push({o: top, depth: depth});
		var r = role(top), n = name(top);
		check('$r:$n has a role', r != "" && r != "unknown" && r != "invalid");
		if (r == "push button" || r == "check box" || r == "slider" || r == "entry" || r == "link" || r == "page tab" || r == "toggle button")
			check('$r has a name', n != "");
		if (parent != null) {
			check('$r:$n: its parent', Atspi.atspi_accessible_get_parent(top, err) == parent);
			check('$r:$n: its index in its parent', Atspi.atspi_accessible_get_index_in_parent(top, err) == index,
				'${Atspi.atspi_accessible_get_index_in_parent(top, err)} != $index');
		}
		var e = extents(top);
		check('$r:$n: extents', e.length == 4 && e[2] >= 0 && e[3] >= 0);
		if (frame != null && e.length == 4 && has(top, 25))
			check('$r:$n: inside its frame', e[0] >= frame[0] - 1 && e[1] >= frame[1] - 1 && e[0] + e[2] <= frame[0] + frame[2] + 1 && e[1] + e[3] <= frame[1] + frame[3] + 1,
				e.join(",") + " in " + frame.join(","));
		for (i in interfaces(top)) {
			var ok = switch i {
				case "org.a11y.atspi.Action": !Atspi.atspi_accessible_get_action_iface(top).isNull() && Atspi.atspi_action_get_n_actions(Atspi.atspi_accessible_get_action_iface(top), err) > 0;
				case "org.a11y.atspi.Text": !Atspi.atspi_accessible_get_text_iface(top).isNull() && Atspi.atspi_text_get_character_count(Atspi.atspi_accessible_get_text_iface(top), err) >= 0;
				case "org.a11y.atspi.Value": !Atspi.atspi_accessible_get_value_iface(top).isNull();
				case "org.a11y.atspi.Table": !Atspi.atspi_accessible_get_table_iface(top).isNull() && Atspi.atspi_table_get_n_rows(Atspi.atspi_accessible_get_table_iface(top), err) > 0;
				case "org.a11y.atspi.Selection": !Atspi.atspi_accessible_get_selection_iface(top).isNull();
				case "org.a11y.atspi.EditableText": !Atspi.atspi_accessible_get_editable_text_iface(top).isNull();
				case _: true;
			}
			check('$r:$n: its $i', ok);
		}
		var kids = children(top);
		for (i in 0...kids.length)
			walk(kids[i], top, i, depth + 1, out, frame ?? e);
		return out;
	}

	static function find(all:Array<{o:Ptr, depth:Int}>, r:String, n:String):Ptr {
		for (x in all)
			if (role(x.o) == r && name(x.o) == n) return x.o;
		return Ptr.nil();
	}

	static function main() {
		var title = Sys.args()[0] ?? "fixture", wanted = Sys.args().slice(1);
		Atspi.atspi_init();
		err.value = Ptr.nil();
		// the application (it may take a moment to embed itself)
		var app = Ptr.nil(), start = haxe.Timer.stamp();
		while (app.isNull() && haxe.Timer.stamp() - start < 15) {
			var desktop = Atspi.atspi_get_desktop(0);
			// (its children asked again: libatspi keeps what it got)
			Atspi.atspi_accessible_clear_cache(desktop);
			for (c in children(desktop))
				if (!c.isNull() && StringTools.startsWith(name(c), title)) app = c;
			// (libatspi learns of new applications from signals: GLib's loop turned)
			if (app.isNull()) pump(0.1);
		}
		check("the application on the desktop", !app.isNull(), [for (c in children(Atspi.atspi_get_desktop(0))) c.isNull() ? "null" : name(c)].join(","));
		if (app.isNull()) {
			Sys.println('AtspiProbe: $checks checks, $failed FAILED');
			Sys.exit(1);
		}
		// (its first frames: the screen settled)
		pump(1);
		var frames = children(app);
		check("its frame", frames.length == 1 && role(frames[0]) == "frame" && StringTools.startsWith(name(frames[0]), title), '${frames.length}');
		if (frames.length == 0) Sys.exit(1);
		var all = walk(frames[0]);
		var shape = [for (x in all) [for (_ in 0...x.depth) "  "].join("") + role(x.o) + ":" + name(x.o)];
		for (w in wanted) {
			var i = w.indexOf(":");
			check('wanted: $w', !find(all, w.substr(0, i), w.substr(i + 1)).isNull());
		}
		if (failed > 0 || Sys.getEnv("ATSPI_DUMP") != null) Sys.println(shape.join("\n"));
		if (title == "fixture") fixture(all);
		Sys.println('AtspiProbe: $title: ${all.length} objects, $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function fixture(all:Array<{o:Ptr, depth:Int}>) {
		var listener = Atspi.atspi_event_listener_new_simple(Callback.addr(onEvent), Ptr.nil());
		for (t in ["object:children-changed", "object:state-changed", "object:text-changed", "object:text-caret-moved", "object:property-change", "object:selection-changed"])
			Arena.scoped(m -> Atspi.atspi_event_listener_register(listener, m.cstring(t), err));
		pump(0.3);
		inline function obj(r:String, n:String):Ptr {
			var o = find(all, r, n);
			check('the fixture\'s $r $n', !o.isNull());
			return o;
		}
		// the table
		var grid = obj("table", "Mail");
		var table = grid.isNull() ? Ptr.nil() : Atspi.atspi_accessible_get_table_iface(grid);
		check("a table's rows and columns", !table.isNull() && Atspi.atspi_table_get_n_rows(table, err) == 3 && Atspi.atspi_table_get_n_columns(table, err) == 2);
		if (!table.isNull()) {
			var cell = Atspi.atspi_table_get_accessible_at(table, 2, 1, err);
			check("a table's cell at a row and column", !cell.isNull() && name(cell) == "Lunch" && role(cell) == "table cell", cell.isNull() ? "none" : name(cell));
			var header = Atspi.atspi_table_get_column_header(table, 1, err);
			check("a column's header", !header.isNull() && name(header) == "Subject" && str(Atspi.atspi_table_get_column_description(table, 1, err)) == "Subject");
			var tc = cell.isNull() ? Ptr.nil() : Atspi.atspi_accessible_get_table_cell(cell);
			var row:Ptr<Int32> = LibC.malloc(8), col:Ptr<Int32> = (cast row : Ptr).add(4);
			row.value = col.value = -1;
			if (!tc.isNull()) Atspi.atspi_table_cell_get_position(tc, row, col, err);
			check("a cell's position", !tc.isNull() && row.value == 2 && col.value == 1, '${row.value},${col.value}');
		}
		var pear = obj("list item", "Pear");
		check("an item's place in its set", attribute(pear, "posinset") == "2" && attribute(pear, "setsize") == "3", attribute(pear, "posinset") + "/" + attribute(pear, "setsize"));
		// text
		var field = obj("entry", "Name");
		var text = Atspi.atspi_accessible_get_text_iface(field);
		check("a field's text", !text.isNull() && str(Atspi.atspi_text_get_text(text, 0, -1, err)) == "Ada" && Atspi.atspi_text_get_character_count(text, err) == 3);
		if (!text.isNull()) {
			var word:Ptr<Int32> = Atspi.atspi_text_get_string_at_offset(text, 1, 1, err);
			check("a field's word at an offset", !word.isNull() && word[0] == 0 && word[1] == 3 && str(((cast word : Ptr).add(8) : Ptr<Ptr>).value) == "Ada");
			check("its selection set", Atspi.atspi_text_set_selection(text, 0, 1, 3, err) != 0);
			pump(0.3);
			var sel:Ptr<Int32> = Atspi.atspi_text_get_selection(text, 0, err);
			check("its selection after", Atspi.atspi_text_get_n_selections(text, err) == 1 && !sel.isNull() && sel[0] == 1 && sel[1] == 3, sel.isNull() ? "none" : '${sel[0]},${sel[1]}');
			check("its caret after", Atspi.atspi_text_get_caret_offset(text, err) == 3);
			check("its focus after", has(field, 12));
			var edit = Atspi.atspi_accessible_get_editable_text_iface(field);
			check("text inserted", !edit.isNull() && Arena.scopedValue(m -> Atspi.atspi_editable_text_insert_text(edit, 3, m.cstring("!"), 1, err)) != 0);
			pump(0.3);
			check("the text after", str(Atspi.atspi_text_get_text(text, 0, -1, err)) == "Ada!", str(Atspi.atspi_text_get_text(text, 0, -1, err)));
			check("the insertion's event", saw("object:text-changed:insert", "Name"), events.join(" "));
			check("the caret's event", saw("object:text-caret-moved", "Name"));
		}
		var code = obj("entry", "Code");
		check("a read-only field: its state, no EditableText", has(code, 43) && !has(code, 7) && interfaces(code).indexOf("org.a11y.atspi.EditableText") < 0);
		var notes = obj("entry", "Notes");
		var nt = Atspi.atspi_accessible_get_text_iface(notes);
		var line:Ptr<Int32> = nt.isNull() ? Ptr.nil() : Atspi.atspi_text_get_string_at_offset(nt, 5, 3, err);
		check("a text area: multi-line, its second line", has(notes, 17) && !line.isNull() && str(((cast line : Ptr).add(8) : Ptr<Ptr>).value) == "two" && line[0] == 4,
			line.isNull() ? "none" : str(((cast line : Ptr).add(8) : Ptr<Ptr>).value) + " " + line[0]);
		// a disclosure expanded through its action
		var more = obj("push button", "More");
		var action = Atspi.atspi_accessible_get_action_iface(more);
		check("a disclosure: collapsed, its actions", has(more, 9) && has(more, 5) && !action.isNull() && Atspi.atspi_action_get_n_actions(action, err) == 2
			&& str(Atspi.atspi_action_get_action_name(action, 1, err)) == "expand");
		if (!action.isNull()) check("expanded through it", Atspi.atspi_action_do_action(action, 1, err) != 0);
		pump(0.5);
		check("expanded after", has(more, 10));
		check("the new child's event", saw("object:children-changed:add"), events.join(" "));
		check("the state's event", saw("object:state-changed:expanded", "More"));
		// a row selected through the table's Selection
		var sel = grid.isNull() ? Ptr.nil() : Atspi.atspi_accessible_get_selection_iface(grid);
		check("a table's selection: the first row", !sel.isNull() && Atspi.atspi_selection_get_n_selected_children(sel, err) == 1 && Atspi.atspi_selection_is_child_selected(sel, 0, err) != 0);
		if (!sel.isNull()) check("the second row selected", Atspi.atspi_selection_select_child(sel, 1, err) != 0);
		pump(0.5);
		var bob = obj("table row", "Bob Lunch");
		check("selected after", has(bob, 23) && !sel.isNull() && Atspi.atspi_selection_is_child_selected(sel, 1, err) != 0);
		check("the selection's events", saw("object:state-changed:selected", "Bob Lunch") && saw("object:selection-changed", "Mail"), events.join(" "));
		// a slider's value set
		var vol = obj("slider", "Volume");
		var value = Atspi.atspi_accessible_get_value_iface(vol);
		check("a slider's value set", !value.isNull() && Atspi.atspi_value_set_current_value(value, 0.8, err) != 0);
		pump(0.3);
		check("its value after", !value.isNull() && Math.abs(Atspi.atspi_value_get_current_value(value, err) - 0.8) < 1e-6, '${Atspi.atspi_value_get_current_value(value, err)}');
		// scrolled into view
		var last = obj("label", "Last");
		var comp = Atspi.atspi_accessible_get_component_iface(last);
		check("scrolled into view", !comp.isNull() && Atspi.atspi_component_scroll_to(comp, 6, err) != 0);
		// the checkbox
		var box = obj("check box", "Remember");
		check("a checkbox's states", has(box, 41) && has(box, 11) && !has(box, 4));
		var ba = Atspi.atspi_accessible_get_action_iface(box);
		if (!ba.isNull()) Atspi.atspi_action_do_action(ba, 0, err);
		pump(0.3);
		check("checked through its action, its event", has(box, 4) && saw("object:state-changed:checked", "Remember"));
		var status = find(all, "panel", "");
		check("a live region's attributes", attribute(status, "live") == "polite" || [for (x in all) if (attribute(x.o, "live") == "polite") x].length == 1);
		// last: Save, which closes the window
		var save = obj("push button", "Save");
		var sa = Atspi.atspi_accessible_get_action_iface(save);
		check("the button's action", !sa.isNull() && Atspi.atspi_action_do_action(sa, 0, err) != 0);
	}
}

@:hxmc.c @:hxmc.lib("libglib-2.0.so.0") extern class GLib {
	static function g_main_context_iteration(context:Ptr, mayBlock:Int):Int;
	static function g_hash_table_lookup(table:Ptr, key:Ptr):Ptr;
}

@:hxmc.c @:hxmc.lib("libatspi.so.0") extern class Atspi {
	static function atspi_init():Int;
	static function atspi_get_desktop(i:Int):Ptr;
	static function atspi_accessible_clear_cache(a:Ptr):Void;
	static function atspi_accessible_get_child_count(a:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_child_at_index(a:Ptr, i:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_parent(a:Ptr, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_index_in_parent(a:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_name(a:Ptr, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_role_name(a:Ptr, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_state_set(a:Ptr):Ptr;
	static function atspi_accessible_get_attributes(a:Ptr, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_interfaces(a:Ptr):Ptr;
	static function atspi_state_set_contains(s:Ptr, state:Int):Int;
	static function atspi_accessible_get_component_iface(a:Ptr):Ptr;
	static function atspi_component_get_extents(c:Ptr, coords:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_component_scroll_to(c:Ptr, type:Int, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_value_iface(a:Ptr):Ptr;
	static function atspi_value_get_current_value(v:Ptr, err:Ptr<Ptr>):Float;
	static function atspi_value_set_current_value(v:Ptr, value:Float, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_action_iface(a:Ptr):Ptr;
	static function atspi_action_get_n_actions(a:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_action_get_action_name(a:Ptr, i:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_action_do_action(a:Ptr, i:Int, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_text_iface(a:Ptr):Ptr;
	static function atspi_text_get_text(t:Ptr, start:Int, end:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_text_get_character_count(t:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_text_get_caret_offset(t:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_text_get_string_at_offset(t:Ptr, offset:Int, granularity:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_text_get_n_selections(t:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_text_get_selection(t:Ptr, i:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_text_set_selection(t:Ptr, i:Int, start:Int, end:Int, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_editable_text_iface(a:Ptr):Ptr;
	static function atspi_editable_text_insert_text(e:Ptr, position:Int, text:Ptr, length:Int, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_table_iface(a:Ptr):Ptr;
	static function atspi_table_get_n_rows(t:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_table_get_n_columns(t:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_table_get_accessible_at(t:Ptr, row:Int, col:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_table_get_column_header(t:Ptr, col:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_table_get_column_description(t:Ptr, col:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_table_cell(a:Ptr):Ptr;
	static function atspi_table_cell_get_position(c:Ptr, row:Ptr<Int32>, col:Ptr<Int32>, err:Ptr<Ptr>):Int;
	static function atspi_accessible_get_selection_iface(a:Ptr):Ptr;
	static function atspi_selection_get_n_selected_children(s:Ptr, err:Ptr<Ptr>):Int;
	static function atspi_selection_select_child(s:Ptr, i:Int, err:Ptr<Ptr>):Int;
	static function atspi_selection_is_child_selected(s:Ptr, i:Int, err:Ptr<Ptr>):Int;
	static function atspi_event_listener_new_simple(cb:Ptr, destroyed:Ptr):Ptr;
	static function atspi_event_listener_register(l:Ptr, type:Ptr, err:Ptr<Ptr>):Int;
}
