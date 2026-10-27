import hxmc.unsafe.*;

// AT-SPI's client side (libatspi, as Orca reads applications): finds the
// application LinuxAccessTest on the desktop, checks its frame's children
// (roles and names), states, extents, value and a live region's attributes,
// then does the Save button's
// action (which ends the application).
//   AtspiProbe
class AtspiProbe {
	static var failed = 0;
	static var checks = 0;

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

	static function children(a:Ptr):Array<Ptr>
		return [for (i in 0...Atspi.atspi_accessible_get_child_count(a, err)) Atspi.atspi_accessible_get_child_at_index(a, i, err)];

	static function main() {
		Atspi.atspi_init();
		err.value = Ptr.nil();
		// the application (it may take a moment to embed itself)
		var app = Ptr.nil(), start = haxe.Timer.stamp();
		while (app.isNull() && haxe.Timer.stamp() - start < 15) {
			var desktop = Atspi.atspi_get_desktop(0);
			// (its children asked again: libatspi keeps what it got)
			Atspi.atspi_accessible_clear_cache(desktop);
			for (c in children(desktop))
				if (!c.isNull() && name(c) == "LinuxAccessTest") app = c;
			// (libatspi learns of new applications from signals: GLib's loop turned)
			if (app.isNull()) {
				for (_ in 0...20)
					GLib.g_main_context_iteration(Ptr.nil(), 0);
				Sys.sleep(0.1);
			}
		}
		check("the application on the desktop", !app.isNull(), [for (c in children(Atspi.atspi_get_desktop(0))) c.isNull() ? "null" : name(c)].join(","));
		if (app.isNull()) {
			Sys.println('AtspiProbe: $checks checks, $failed FAILED');
			Sys.exit(1);
		}
		var frames = children(app);
		check("its frame", frames.length == 1 && str(Atspi.atspi_accessible_get_role_name(frames[0], err)) == "frame" && name(frames[0]) == "LinuxAccessTest",
			'${frames.length}');
		var kids = frames.length > 0 ? children(frames[0]) : [];
		var shape = [for (k in kids) str(Atspi.atspi_accessible_get_role_name(k, err)) + ":" + name(k)];
		check("the widgets: roles and names", shape.join(",") == "label:Settings,push button:Save,check box:Remember,slider:Volume,entry:Name,panel:", shape.join(","));
		if (kids.length == 6) {
			var states = Atspi.atspi_accessible_get_state_set(kids[2]);
			check("a checkbox's states", Atspi.atspi_state_set_contains(states, 41) != 0 && Atspi.atspi_state_set_contains(states, 11) != 0
				&& Atspi.atspi_state_set_contains(states, 4) == 0);
			var comp = Atspi.atspi_accessible_get_component_iface(kids[1]);
			var r:Ptr<Int32> = comp.isNull() ? Ptr.nil() : Atspi.atspi_component_get_extents(comp, 0, err);
			check("a button's extents", !r.isNull() && r[2] > 20 && r[3] > 10, r.isNull() ? "none" : '${r[2]}x${r[3]}');
			var value = Atspi.atspi_accessible_get_value_iface(kids[3]);
			check("a slider's value", !value.isNull() && Atspi.atspi_value_get_current_value(value, err) == 0.5);
			var attrs = Atspi.atspi_accessible_get_attributes(kids[5], err);
			var live = attrs.isNull() ? Ptr.nil() : GLib.g_hash_table_lookup(attrs, Mem.cstr("live"));
			check("a live region's attributes", !live.isNull() && str(live) == "polite", live.isNull() ? "none" : str(live));
			var action = Atspi.atspi_accessible_get_action_iface(kids[1]);
			check("the button's action", !action.isNull() && Atspi.atspi_action_do_action(action, 0, err) != 0);
		}
		Sys.println('AtspiProbe: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
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
	static function atspi_accessible_get_name(a:Ptr, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_role_name(a:Ptr, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_state_set(a:Ptr):Ptr;
	static function atspi_accessible_get_attributes(a:Ptr, err:Ptr<Ptr>):Ptr;
	static function atspi_state_set_contains(s:Ptr, state:Int):Int;
	static function atspi_accessible_get_component_iface(a:Ptr):Ptr;
	static function atspi_component_get_extents(c:Ptr, coords:Int, err:Ptr<Ptr>):Ptr;
	static function atspi_accessible_get_value_iface(a:Ptr):Ptr;
	static function atspi_value_get_current_value(v:Ptr, err:Ptr<Ptr>):Float;
	static function atspi_accessible_get_action_iface(a:Ptr):Ptr;
	static function atspi_action_do_action(a:Ptr, i:Int, err:Ptr<Ptr>):Int;
}
