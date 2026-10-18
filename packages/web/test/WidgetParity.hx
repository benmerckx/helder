// The DOM's widgets against hxmc.ui's, which they stand for in a page
// (@:renderer on ui's Widgets): read by WidgetDocs from both sources, every
// ui widget a DOM one of the same name, with the same props: names, types,
// whether optional, and the defaults both state (tag, the DOM's element id,
// and style, a function of a drawn node's states, aside). A difference not
// in KNOWN fails, as one in KNOWN that is gone (its entry then removed); a
// widget of one definition for both (@:neutral) has no DOM copy:
// the two sets drift apart only knowingly, until each widget is one
// definition for both (docs/plans/native-or-drawn.md).
//   WidgetParity <ui Widgets.hx> <web Widgets.hx>
class WidgetParity {
	// the differences known, by widget, and why
	static final KNOWN = [
		"Checkbox" => "invalid: the DOM's only (aria-invalid)",
		"FieldLabel" => "htmlFor: the DOM's only (a <label>'s for)",
		"Input" => "type: the DOM's only (an <input>'s type)",
		"Select" => "size: ui's only (data-size)",
		"AlertDialog" => "size: ui's only (data-size)",
		"NativeSelect" => "size: ui's only (data-size); disabled: the DOM's only",
		"Avatar" => "size: the DOM's only",
		"BarChart" => "stacked: ui's only",
		"LineChart" => "stacked: ui's only",
		"AreaChart" => "stacked: ui's only"
	];

	static final ASIDE = ["tag", "style"];

	static function main() {
		var args = Sys.args();
		var ui:Array<Dynamic> = WidgetDocs.read(sys.io.File.getContent(args[0]), null);
		var dom:Array<Dynamic> = WidgetDocs.read(sys.io.File.getContent(args[1]), null);
		var byName = [for (w in dom) (w.name : String) => w];
		var failed = 0, known = 0;
		function fail(msg:String) {
			Sys.println("WidgetParity: FAIL: " + msg);
			failed++;
		}
		for (u in ui) {
			var name:String = u.name, d = byName.get(name);
			// (one definition for both: no DOM copy to differ, none to keep)
			if (u.neutral == true) {
				if (d != null) fail('$name: one definition for both (@:neutral), its DOM copy still there');
				if (KNOWN.exists(name)) fail('$name: one definition for both (@:neutral); KNOWN\'s entry is stale');
				continue;
			}
			if (d == null) {
				fail('$name: no DOM version');
				continue;
			}
			var diffs = differences(u.props, d.props);
			if (diffs.length > 0 && KNOWN.exists(name)) known++;
			else if (diffs.length > 0) fail('$name: ' + diffs.join("; "));
			else if (KNOWN.exists(name)) fail('$name: the same now; KNOWN\'s entry ("${KNOWN[name]}") is stale');
		}
		Sys.println('WidgetParity: ${ui.length} widgets, $known known to differ' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}

	// (props only one has, or with another type, optionality or default)
	static function differences(a:Array<Dynamic>, b:Array<Dynamic>):Array<String> {
		var out = [];
		for (p in a) {
			if (ASIDE.indexOf(p.name) >= 0) continue;
			var q:Dynamic = Lambda.find(b, (q:Dynamic) -> q.name == p.name);
			if (q == null) out.push('${p.name}: ui\'s only');
			else if (type(p.type) != type(q.type)) out.push('${p.name}: ${p.type} (ui) vs ${q.type}');
			else if (p.optional != q.optional) out.push('${p.name}: optional in one only');
			else if (p.def != null && q.def != null && value(p.def) != value(q.def)) out.push('${p.name}: default ${p.def} (ui) vs ${q.def}');
		}
		for (q in b)
			if (ASIDE.indexOf(q.name) < 0 && !Lambda.exists(a, (p:Dynamic) -> p.name == q.name)) out.push('${q.name}: the DOM\'s only');
		return out;
	}

	// (a type as written, its packages and spaces aside: Color, hxmc.ui.Color)
	static function type(t:String):String
		return ~/\s+/g.replace(~/\b[a-z][a-z0-9]*\./g.replace(t, ""), "");

	// (a default: 120.0 and 120 the same)
	static function value(v:String):String {
		var f = Std.parseFloat(v);
		return Math.isNaN(f) ? v : Std.string(f);
	}
}
