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
// ring's visibility, an attribute, the variant or size, the sheet, dark,
// the direction (rtl, ltr), the first draw (starting: CSS's @starting-style),
// the window's width across a breakpoint (sm, md, lg, xl, 2xl: Tailwind's).
// States of other nodes, as Tailwind's variants: "group:hover" holds while
// an ancestor marked with a "group" attribute is hovered ("group/item:..."
// one whose group attribute names item among its words), "peer:checked"
// while an earlier sibling marked "peer" holds it, "has:data-state=open"
// while a descendant does ("has:>x": a child), "first" and "last" for the
// first and last child, "not:x" while x does not; "data-slot=x" is the
// node's slot. They nest ("group:has:focus").
class Rules {
	// (whether a rule anywhere asks for another node's states, so that its changes restyle: group, peer, has, first or last)
	static var relational = 0;
	static inline var GROUP = 1;
	static inline var PEER = 2;
	static inline var HAS = 4;
	static inline var PLACE = 8;

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
			if (m.current) want = withCurrent(name, want, current);
			var cur = n.style.target(name);
			var k = applied == null ? -1 : applied.indexOf(name);
			// (the node's own value: left as it is)
			if (k >= 0 ? !same(cur, appliedValues[k]) : !same(cur, initial(name))) continue;
			if (!same(cur, want)) StyleFields.set(n.style, name, want);
			if (names == null) {
				names = [];
				values = [];
			}
			names.push(name);
			values.push(n.style.target(name));
		}
		// (what the rules wrote and no longer set, still as they wrote it: back to the default)
		if (applied != null)
			for (k in 0...applied.length) {
				var name = applied[k];
				if ((names == null || names.indexOf(name) < 0) && same(n.style.target(name), appliedValues[k]))
					StyleFields.set(n.style, name, initial(name));
			}
		@:privateAccess n.themedNames = names;
		@:privateAccess n.themedValues = values;
		@:privateAccess n.themePseudo(m.placeholder == null ? null : colorWithCurrent(m.placeholder, current),
			m.selection == null ? null : colorWithCurrent(m.selection, current));
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
		// (lengths naming the sheet's: radii, one corner's)
		var lengths = sheet == null ? null : sheet.lengths;
		if (Length.isToken(scratch.radius)) scratch.radius = Math.max(0, Length.resolve(scratch.radius, lengths));
		var cr = scratch.corners;
		if (cr != null && (Length.isToken(cr.topLeft) || Length.isToken(cr.topRight) || Length.isToken(cr.bottomRight) || Length.isToken(cr.bottomLeft)))
			scratch.corners = new Corners(Length.resolve(cr.topLeft, lengths), Length.resolve(cr.topRight, lengths), Length.resolve(cr.bottomRight, lengths),
				Length.resolve(cr.bottomLeft, lengths));
		var names = [], values:Array<Dynamic> = [], current = false;
		for (name in StyleFields.NAMES) {
			var v = StyleFields.get(scratch, name);
			if (same(v, initial(name))) continue;
			names.push(name);
			values.push(v);
		}
		current = usesCurrent(scratch);
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

	static function usesCurrent(st:Style):Bool {
		var colors:Array<Null<Color>> = [st.background, st.borderColor, st.color, st.outlineColor, st.ringColor, st.ringOffsetColor, st.textDecorationColor,
			st.scrollbarColor, st.scrollbarTrackColor];
		for (c in colors)
			if (c != null && c.isToken) return true;
		return shadowUsesCurrent(st.shadow) || shadowUsesCurrent(st.textShadow);
	}

	static function shadowUsesCurrent(sh:Null<Shadow>):Bool {
		var s = sh;
		while (s != null) {
			if (s.color.isToken) return true;
			s = s.next;
		}
		return false;
	}

	// (the properties that are a colour, by Style's names)
	static final COLORS = ["background", "borderColor", "color", "outlineColor", "ringColor", "ringOffsetColor", "textDecorationColor", "scrollbarColor",
		"scrollbarTrackColor"];

	// (a value with currentColor, a token's alpha kept, as a node's colour)
	static function withCurrent(name:String, v:Dynamic, current:Color):Dynamic {
		if (v == null) return v;
		if (COLORS.indexOf(name) >= 0) return colorWithCurrent(v, current);
		if ((name == "shadow" || name == "textShadow") && shadowUsesCurrent(v)) return resolveShadow(v, null, current);
		return v;
	}

	static function colorWithCurrent(c:Color, current:Color):Color
		return c.isToken ? current.fade(c.tokenAlpha()) : c;

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
			case "rtl": n.rtl();
			case "sm" | "md" | "lg" | "xl" | "2xl": ui.width >= Ui.BREAKPOINTS.get(w);
			case "starting":
				// (CSS's @starting-style: until its first draw; then again, its transition easing from these)
				@:privateAccess n.style.starting = true;
				!@:privateAccess n.style.drawn;
			case "ltr": !n.rtl();
			case "first": n.parent != null && n.parent.children[0] == n;
			case "last": n.parent != null && n.parent.children[n.parent.children.length - 1] == n;
			case _:
				var colon = w.indexOf(":");
				if (colon > 0) {
					var head = w.substr(0, colon), inner = w.substr(colon + 1);
					var slash = head.indexOf("/"), name = slash < 0 ? null : head.substr(slash + 1);
					switch slash < 0 ? head : head.substr(0, slash) {
						case "not": !holds(n, ui, inner);
						case "group":
							var p = n.parent;
							while (p != null && !(marked(p, "group", name) && holds(p, ui, inner)))
								p = p.parent;
							p != null;
						case "peer":
							var found = false;
							if (n.parent != null)
								for (c in n.parent.children) {
									if (c == n) break;
									if (marked(c, "peer", name) && holds(c, ui, inner)) {
										found = true;
										break;
									}
								}
							found;
						case "has":
							StringTools.startsWith(inner, ">") ? Lambda.exists(n.children, c -> holds(c, ui, inner.substr(1))) : below(n, ui, inner);
						case _: false;
					}
				} else {
					var eq = w.indexOf("=");
					if (eq < 0) n.attr(w) != null else {
						var key = w.substr(0, eq), value = w.substr(eq + 1);
						key == "data-slot" ? n.slot == value : n.attr(key) == value;
					}
				}
		}
	}

	// (whether n is marked as a group or peer: the attribute, naming name among its words when given)
	static function marked(n:Node, attr:String, name:Null<String>):Bool {
		var v = n.attr(attr);
		return v != null && (name == null || v.split(" ").indexOf(name) >= 0);
	}

	// (whether a descendant of n holds w)
	static function below(n:Node, ui:Ui, w:String):Bool {
		for (c in n.children)
			if (holds(c, ui, w) || below(c, ui, w)) return true;
		return false;
	}

	// (what rules over other nodes' states w asks for)
	static function relations(w:String):Int {
		var r = 0, colon = w.indexOf(":");
		if (w == "first" || w == "last") r |= PLACE;
		if (colon > 0) {
			var head = w.substr(0, colon);
			if (StringTools.startsWith(head, "group")) r |= GROUP;
			if (StringTools.startsWith(head, "peer")) r |= PEER;
			if (head == "has") r |= HAS;
			r |= relations(w.substr(colon + 1));
		}
		return r;
	}

	// (n's states or attributes changed: the nodes whose rules over other nodes' states may follow, restyled)
	@:allow(hxmc.ui.Node) @:allow(hxmc.ui.Ui) static function related(n:Node) {
		if (relational == 0 || n.ui == null) return;
		if (relational & GROUP != 0 && n.attr("group") != null)
			for (c in n.children)
				restyleTree(c);
		if (relational & PEER != 0 && n.attr("peer") != null && n.parent != null) {
			var after = false;
			for (c in n.parent.children) {
				if (after) restyleTree(c);
				if (c == n) after = true;
			}
		}
		if (relational & HAS != 0) {
			var p = n.parent;
			while (p != null) {
				@:privateAccess p.restyleLater();
				p = p.parent;
			}
		}
	}

	// (parent's children changed, child put in or taken out, first and last
	// maybe others: theirs, the peers' siblings', and the ancestors' has rules, restyled)
	@:allow(hxmc.ui.Node) static function placed(parent:Node, child:Null<Node>, first:Null<Node>, last:Null<Node>) {
		if (relational == 0 || parent.ui == null) return;
		if (relational & PLACE != 0) {
			if (first != null) @:privateAccess first.restyleLater();
			if (last != null) @:privateAccess last.restyleLater();
			var c = parent.children;
			if (c.length > 0) {
				@:privateAccess c[0].restyleLater();
				@:privateAccess c[c.length - 1].restyleLater();
			}
		}
		if (relational & PEER != 0 && (child == null ? Lambda.exists(parent.children, c -> c.attr("peer") != null) : child.attr("peer") != null))
			for (c in parent.children)
				restyleTree(c);
		if (relational & HAS != 0) {
			var p = parent;
			while (p != null) {
				@:privateAccess p.restyleLater();
				p = p.parent;
			}
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
		if (s.ringColor != null) s.ringColor = resolve(s.ringColor, tokens, current, dark);
		s.ringOffsetColor = resolve(s.ringOffsetColor, tokens, current, dark);
		if (s.textDecorationColor != null) s.textDecorationColor = resolve(s.textDecorationColor, tokens, current, dark);
		if (s.scrollbarColor != null) s.scrollbarColor = resolve(s.scrollbarColor, tokens, current, dark);
		if (s.scrollbarTrackColor != null) s.scrollbarTrackColor = resolve(s.scrollbarTrackColor, tokens, current, dark);
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
		// (auto margins: NaN, the same as NaN)
		if (Std.isOfType(a, Float) && Std.isOfType(b, Float)) return Math.isNaN(a) && Math.isNaN(b);
		if (Reflect.isEnumValue(a) && Reflect.isEnumValue(b)) return Type.enumEq(a, b);
		if (Std.isOfType(a, Edges) && Std.isOfType(b, Edges)) {
			var x:Edges = a, y:Edges = b;
			inline function side(p:Float, q:Float):Bool
				return p == q || Math.isNaN(p) && Math.isNaN(q);
			return side(x.top, y.top) && side(x.right, y.right) && side(x.bottom, y.bottom) && side(x.left, y.left);
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
			if (r.when != null)
				for (w in r.when)
					relational |= relations(w);
			var l = m.get(r.slot);
			if (l == null) m.set(r.slot, l = []);
			l.push(r);
		}
		return m;
	}
}

// (a merge of rules: Rules.merged)
private typedef Merge = {names:Array<String>, values:Array<Dynamic>, placeholder:Null<Color>, selection:Null<Color>, current:Bool};
