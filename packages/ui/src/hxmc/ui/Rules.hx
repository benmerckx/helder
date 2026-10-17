package hxmc.ui;

// A theme's rules applied to the nodes with a slot (Node.slot): the rules
// of the nearest sheet (Node.theme, else Ui.theme) for the node's slot,
// variant and size whose states all hold, merged in order on a fresh
// style, their token colours resolved with the sheet's light or dark
// colours (Ui.dark); each property the merge sets that the node has not
// set itself (its value still the default, or still what the rules last
// wrote) written, and those the rules no longer set taken back to the
// default. Again whenever a state changes: hover, press, focus, the focus
// ring's visibility, an attribute, the variant or size, the sheet, dark.
class Rules {
	public static function restyle(n:Node) {
		var ui = n.ui;
		if (ui == null) return;
		var sheet = n.sheet();
		var applied = @:privateAccess n.themed;
		if ((n.slot == null || sheet == null) && applied == null) {
			@:privateAccess n.themePlaceholder(null);
			return;
		}
		var tokens = sheet == null ? null : ui.dark && sheet.dark != null ? sheet.dark : sheet.light;
		var rules = n.slot == null || sheet == null ? null : index(sheet).get(n.slot);
		// (the rules merged on a fresh style; a placeholder's colour on its own)
		var scratch = new Node().style, placeholder:Null<Color> = null;
		if (rules != null)
			for (r in rules) {
				if (r.variant != null && r.variant != n.variant || r.size != null && r.size != n.size) continue;
				var ok = true, forPlaceholder = false;
				if (r.when != null)
					for (w in r.when) {
						if (w == "placeholder") forPlaceholder = true else if (!holds(n, ui, w)) {
							ok = false;
							break;
						}
					}
				if (!ok) continue;
				if (forPlaceholder) {
					if (r.style.color != null) placeholder = r.style.color;
				} else scratch.set(r.style);
			}
		resolveColors(scratch, tokens);
		var base = defaults(), next:Null<Map<String, Dynamic>> = null;
		for (name in StyleFields.NAMES) {
			var want = StyleFields.get(scratch, name), was = StyleFields.get(base, name);
			var cur = StyleFields.get(n.style, name);
			var had = applied != null && applied.exists(name);
			// (the node's own value: left as it is)
			if (had ? !same(cur, applied.get(name)) : !same(cur, was)) continue;
			if (!same(want, was)) {
				if (!same(cur, want)) StyleFields.set(n.style, name, want);
				if (next == null) next = new Map();
				next.set(name, StyleFields.get(n.style, name));
			} else if (had) StyleFields.set(n.style, name, was);
		}
		@:privateAccess n.themed = next;
		@:privateAccess n.themePlaceholder(placeholder == null ? null : resolve(placeholder, tokens));
	}

	// restyles n and its subtree
	public static function restyleTree(n:Node) {
		if (n.slot != null || @:privateAccess n.themed != null) restyle(n);
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
	// a name the sheet lacks: transparent), else the colour itself
	public static function resolve(c:Color, tokens:Null<Map<String, Color>>):Color {
		if (!c.isToken) return c;
		var v = tokens == null ? null : tokens.get(c.tokenName());
		return v == null ? Color.TRANSPARENT : v.fade(c.tokenAlpha());
	}

	// (the colours a rule can give, tokens resolved: background, text, border, outline, decoration, shadows')
	static function resolveColors(s:Style, tokens:Null<Map<String, Color>>) {
		s.background = resolve(s.background, tokens);
		s.borderColor = resolve(s.borderColor, tokens);
		if (s.color != null) s.color = resolve(s.color, tokens);
		if (s.outlineColor != null) s.outlineColor = resolve(s.outlineColor, tokens);
		if (s.textDecorationColor != null) s.textDecorationColor = resolve(s.textDecorationColor, tokens);
		if (s.shadow != null) s.shadow = resolveShadow(s.shadow, tokens);
		if (s.textShadow != null) s.textShadow = resolveShadow(s.textShadow, tokens);
	}

	static function resolveShadow(sh:Shadow, tokens:Null<Map<String, Color>>):Shadow {
		if (sh == Shadow.NONE) return sh;
		var first:Null<Shadow> = null, last:Null<Shadow> = null, s:Null<Shadow> = sh;
		while (s != null) {
			var c:Shadow = {
				x: s.x,
				y: s.y,
				blur: s.blur,
				spread: s.spread,
				color: resolve(s.color, tokens),
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
	static var base:Null<Style> = null;

	static function defaults():Style {
		if (base == null) base = new Node().style;
		return base;
	}

	// (each sheet's rules by slot, in their order; made when a sheet is first used)
	static final indexes = new haxe.ds.ObjectMap<{}, Map<String, Array<Rule>>>();

	static function index(sheet:StyleSheet):Map<String, Array<Rule>> {
		var m = indexes.get(sheet);
		if (m != null) return m;
		m = new Map();
		for (r in sheet.rules) {
			var l = m.get(r.slot);
			if (l == null) m.set(r.slot, l = []);
			l.push(r);
		}
		indexes.set(sheet, m);
		return m;
	}
}
