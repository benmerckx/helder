package hxmc.ui;

// A theme's rules applied to the nodes with a slot (Node.slot): those of
// the nearest sheet (Node.theme, else Ui.theme), or without one the base
// rules (the widgets' unstyled looks, addBase: a sheet starts from none
// of them, as Tailwind's preflight from none of a browser's), for the
// node's slot, variant and size whose states all hold, merged in order on a fresh style, their token
// colours resolved with the sheet's light or dark colours (Ui.dark;
// "currentColor" as the node's text colour); each property the merge sets that the node has not
// set itself (its value still the default, or still what the rules last
// wrote) written, and those the rules no longer set taken back to the
// default. Again whenever a state changes: hover, press, focus, the focus
// ring's visibility, an attribute, the variant or size, the sheet, dark.
class Rules {
	// the base rules: the widgets' unstyled looks, where no sheet applies (added once each: addBase)
	static final base:Array<Rule> = [];
	static final bases = new Map<String, Bool>();
	static var baseIndex:Null<Map<String, Array<Rule>>> = null;

	// adds base rules under a name (again: nothing)
	public static function addBase(name:String, rules:Array<Rule>) {
		if (bases.exists(name)) return;
		bases.set(name, true);
		for (r in rules)
			base.push(r);
		baseIndex = null;
	}

	public static function restyle(n:Node) {
		var ui = n.ui;
		if (ui == null) return;
		var sheet = n.sheet();
		var applied = @:privateAccess n.themedNames, appliedValues = @:privateAccess n.themedValues;
		if (n.slot == null && applied == null) {
			@:privateAccess n.themePseudo(null, null);
			return;
		}
		if (baseIndex == null) baseIndex = indexOf(base);
		var rules = n.slot == null ? null : sheet != null ? index(sheet).get(n.slot) : baseIndex.get(n.slot);
		// (the rules that hold, by their place: what the merge is kept by)
		var key = new StringBuf();
		key.add(sheet == null ? 0 : sheetId(sheet));
		key.add(ui.dark ? "d" : "l");
		key.add(n.slot);
		if (rules != null)
			for (k in 0...rules.length) {
				var r = rules[k];
				if (r.variant != null && r.variant != n.variant || r.size != null && r.size != n.size) continue;
				var ok = true;
				if (r.when != null)
					for (w in r.when)
						if (w != "placeholder" && w != "selection" && !holds(n, ui, w)) {
							ok = false;
							break;
						}
				if (ok) {
					key.add(",");
					key.add(k);
				}
			}
		var m = rules == null ? NONE : merged(key.toString(), rules, sheet, ui.dark);
		// (currentColor, when the merge uses it: the colour it gives the text, else the node's own, else its parent's)
		var current = Color.BLACK;
		if (m.current) {
			var given = m.names.indexOf("color");
			current = given >= 0 ? (m.values[given] : Color) : n.style.color != null && !(applied != null && applied.indexOf("color") >= 0) ? n.style.color : n.parent != null ? n.parent.textColor() : Color.BLACK;
			if (current.isToken) current = Color.BLACK;
		}
		var names:Null<Array<String>> = null, values:Null<Array<Dynamic>> = null;
		for (i in 0...m.names.length) {
			var name = m.names[i], want:Dynamic = m.values[i];
			if (m.current) want = withCurrent(want, current);
			var cur = StyleFields.get(n.style, name);
			var k = applied == null ? -1 : applied.indexOf(name);
			// (the node's own value: left as it is)
			if (k >= 0 ? !same(cur, appliedValues[k]) : !same(cur, initial(name))) continue;
			if (!same(cur, want)) StyleFields.set(n.style, name, want);
			if (names == null) {
				names = [];
				values = [];
			}
			names.push(name);
			values.push(StyleFields.get(n.style, name));
		}
		// (what the rules wrote and no longer set, still as they wrote it: back to the default)
		if (applied != null)
			for (k in 0...applied.length) {
				var name = applied[k];
				if ((names == null || names.indexOf(name) < 0) && same(StyleFields.get(n.style, name), appliedValues[k]))
					StyleFields.set(n.style, name, initial(name));
			}
		@:privateAccess n.themedNames = names;
		@:privateAccess n.themedValues = values;
		@:privateAccess n.themePseudo(m.placeholder == null ? null : withCurrent(m.placeholder, current),
			m.selection == null ? null : withCurrent(m.selection, current));
	}

	// (a merge: the properties it sets and their values, tokens resolved but
	// currentColor, which a node resolves; its placeholder's colour, its
	// selection's: the "placeholder" rules' color, the "selection" rules' background)
	static final NONE:Merge = {names: [], values: [], placeholder: null, selection: null, current: false};
	static final merges = new Map<String, Merge>();
	static final sheetIds = new haxe.ds.ObjectMap<{}, Int>();

	static function sheetId(sheet:StyleSheet):Int {
		var id = sheetIds.get(sheet);
		if (id == null) sheetIds.set(sheet, id = Lambda.count(sheetIds) + 1);
		return id;
	}

	static function merged(key:String, rules:Array<Rule>, sheet:Null<StyleSheet>, dark:Bool):Merge {
		var m = merges.get(key);
		if (m != null) return m;
		var tokens = sheet == null ? null : dark && sheet.dark != null ? sheet.dark : sheet.light;
		var scratch = new Node().style, placeholder:Null<Color> = null, selection:Null<Color> = null;
		var parts = key.split(",");
		for (k in 1...parts.length) {
			var r = rules[Std.parseInt(parts[k])];
			if (r.when != null && r.when.indexOf("placeholder") >= 0) {
				if (r.style.color != null) placeholder = r.style.color;
			} else if (r.when != null && r.when.indexOf("selection") >= 0) {
				if (r.style.background != null) selection = r.style.background;
			} else scratch.set(r.style);
		}
		resolveColors(scratch, tokens, CURRENT, dark);
		var names = [], values:Array<Dynamic> = [], current = false;
		for (name in StyleFields.NAMES) {
			var v = StyleFields.get(scratch, name);
			if (same(v, initial(name))) continue;
			names.push(name);
			values.push(v);
			if (usesCurrent(v)) current = true;
		}
		if (placeholder != null) {
			placeholder = resolve(placeholder, tokens, CURRENT, dark);
			if (placeholder.isToken) current = true;
		}
		if (selection != null) {
			selection = resolve(selection, tokens, CURRENT, dark);
			if (selection.isToken) current = true;
		}
		m = {names: names, values: values, placeholder: placeholder, selection: selection, current: current};
		merges.set(key, m);
		return m;
	}

	// (currentColor kept through a merge: its own token, resolved per node)
	static final CURRENT = Color.token("currentcolor");

	static function usesCurrent(v:Dynamic):Bool {
		if (Std.isOfType(v, Int)) return (v : Color).isToken;
		if (Std.isOfType(v, Shadow)) {
			var s:Null<Shadow> = v;
			while (s != null) {
				if (s.color.isToken) return true;
				s = s.next;
			}
		}
		return false;
	}

	// (a value with currentColor, a token's alpha kept, as a node's colour)
	static function withCurrent(v:Dynamic, current:Color):Dynamic {
		if (Std.isOfType(v, Int)) {
			var c:Color = v;
			return c.isToken ? current.fade(c.tokenAlpha()) : c;
		}
		if (Std.isOfType(v, Shadow) && usesCurrent(v)) return resolveShadow(v, null, current);
		return v;
	}

	// restyles n and its subtree (at the next update)
	public static function restyleTree(n:Node) {
		@:privateAccess n.restyleLater();
		for (c in n.children)
			restyleTree(c);
	}

	// whether a state holds for n
	static function holds(n:Node, ui:Ui, w:String):Bool {
		return switch w {
			case "hover": n.hovered;
			case "active": n.pressed;
			case "focus": n.focused;
			case "focus-visible": n.focused && ui.focusVisible;
			case "disabled": n.attr("disabled") != null || n.attr("data-disabled") != null;
			case "dark": ui.dark;
			case _:
				var eq = w.indexOf("=");
				eq < 0 ? n.attr(w) != null : n.attr(w.substr(0, eq)) == w.substr(eq + 1);
		}
	}

	// a token reference as the sheet's colour (its alpha times the reference's;
	// "currentColor" as current; Canvas and CanvasText, where the sheet has
	// none, as Chromium's, light or dark; another name the sheet lacks:
	// transparent), else the colour itself
	public static function resolve(c:Color, tokens:Null<Map<String, Color>>, current:Color, dark = false):Color {
		if (!c.isToken) return c;
		var name = c.tokenName();
		if (name == "currentcolor") return current.isToken ? c : current.fade(c.tokenAlpha());
		var v = tokens == null ? null : tokens.get(name);
		if (v == null && name == "canvas") v = dark ? Color.rgb(0x121212) : Color.WHITE;
		if (v == null && name == "canvastext") v = dark ? Color.WHITE : Color.BLACK;
		return v == null ? Color.TRANSPARENT : v.fade(c.tokenAlpha());
	}

	// (the colours a rule can give, tokens resolved: background, text, border, outline, decoration, shadows')
	static function resolveColors(s:Style, tokens:Null<Map<String, Color>>, current:Color, dark:Bool) {
		s.background = resolve(s.background, tokens, current, dark);
		s.borderColor = resolve(s.borderColor, tokens, current, dark);
		if (s.color != null) s.color = resolve(s.color, tokens, current, dark);
		if (s.outlineColor != null) s.outlineColor = resolve(s.outlineColor, tokens, current, dark);
		if (s.textDecorationColor != null) s.textDecorationColor = resolve(s.textDecorationColor, tokens, current, dark);
		if (s.shadow != null) s.shadow = resolveShadow(s.shadow, tokens, current, dark);
		if (s.textShadow != null) s.textShadow = resolveShadow(s.textShadow, tokens, current, dark);
	}

	static function resolveShadow(sh:Shadow, tokens:Null<Map<String, Color>>, current:Color, dark = false):Shadow {
		if (sh == Shadow.NONE) return sh;
		var first:Null<Shadow> = null, last:Null<Shadow> = null, s:Null<Shadow> = sh;
		while (s != null) {
			var c:Shadow = {
				x: s.x,
				y: s.y,
				blur: s.blur,
				spread: s.spread,
				color: resolve(s.color, tokens, current, dark),
				inset: s.inset,
				currentColor: s.currentColor
			};
			if (first == null) first = c else last.next = c;
			last = c;
			s = s.next;
		}
		return first;
	}

	// (whether two values of a property are the same: enums by their cases, edges by their sides)
	static function same(a:Dynamic, b:Dynamic):Bool {
		if (a == b) return true;
		if (a == null || b == null) return false;
		if (Reflect.isEnumValue(a) && Reflect.isEnumValue(b)) return Type.enumEq(a, b);
		if (Std.isOfType(a, Edges) && Std.isOfType(b, Edges)) {
			var x:Edges = a, y:Edges = b;
			return x.top == y.top && x.right == y.right && x.bottom == y.bottom && x.left == y.left;
		}
		return false;
	}

	// (a fresh style's values: where a property the rules no longer set goes back)
	static var fresh:Null<Style> = null;

	static inline function initial(name:String):Dynamic {
		if (fresh == null) fresh = new Node().style;
		return StyleFields.get(fresh, name);
	}

	// (each sheet's rules by slot, in their order; made when a sheet is first used)
	static final indexes = new haxe.ds.ObjectMap<{}, Map<String, Array<Rule>>>();

	static function index(sheet:StyleSheet):Map<String, Array<Rule>> {
		var m = indexes.get(sheet);
		if (m != null) return m;
		m = indexOf(sheet.rules);
		indexes.set(sheet, m);
		return m;
	}

	static function indexOf(rules:Array<Rule>):Map<String, Array<Rule>> {
		var m = new Map<String, Array<Rule>>();
		for (r in rules) {
			var l = m.get(r.slot);
			if (l == null) m.set(r.slot, l = []);
			l.push(r);
		}
		return m;
	}
}

// (a merge of rules: Rules.merged)
private typedef Merge = {names:Array<String>, values:Array<Dynamic>, placeholder:Null<Color>, selection:Null<Color>, current:Bool};
