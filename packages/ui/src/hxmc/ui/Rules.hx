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
// while a descendant does ("has:>x": a child; "has:x&y" one holding both), "first" and "last" for the
// first and last child, "not:x" while x does not, "prev:x" while the
// sibling before holds x (CSS's [x]+&), "parent:x" while the
// parent holds x (a rule of slot "*": any slot's, after its own, as an
// arbitrary selector of a slot's children); "variant=x" and "size=x" the
// node's variant and size; "data-slot=x" is the
// node's slot; "svg" holds for an icon (an image of an Svg: "has:>svg", a
// button's icon, as CSS's :has(>svg)). They nest ("group:has:focus").
class Rules {
	// (whether a rule anywhere asks for another node's states, so that its changes restyle: group, peer, has, first or last)
	static var relational = 0;
	static inline var GROUP = 1;
	static inline var PEER = 2;
	static inline var HAS = 4;
	static inline var PLACE = 8;
	static inline var PARENT = 16;
	static inline var PREV = 32;
	// (a relation within one: "group:has:x", a group's descendant's state)
	static inline var NESTED = 64;

	// the base rules: the widgets' unstyled looks, where no sheet applies (added once each: addBase)
	static final base:Array<Rule> = [];
	static final bases = new Map<String, Bool>();
	static var baseIndex:Null<Map<String, Array<Indexed>>> = null;

	// adds base rules under a name (again: nothing)
	public static function addBase(name:String, rules:Array<Rule>) {
		if (bases.exists(name)) return;
		bases.set(name, true);
		for (r in rules)
			base.push(r);
		baseIndex = null;
	}

	// holds n's own values of the named properties (StyleProps's fields;
	// padding, margin, inset: their sides too) over the rules, its defaults
	// too, as an instance's className over its slot's classes (a combobox's
	// popover-content p-0)
	public static function keep(n:Node, names:Array<String>) {
		var ids = @:privateAccess n.keptIds ?? [];
		for (name in names)
			for (f in [name, name + "Top", name + "Right", name + "Bottom", name + "Left"]) {
				var id = StyleFields.NAMES.indexOf(f);
				if (id >= 0 && ids.indexOf(id) < 0) ids.push(id);
			}
		@:privateAccess n.keptIds = ids;
		@:privateAccess n.restyleLater();
	}

	public static function restyle(n:Node) {
		var ui = n.ui;
		if (ui == null) return;
		var sheet = n.sheet();
		var applied = @:privateAccess n.themedIds, appliedValues = @:privateAccess n.themedValues, kept = @:privateAccess n.keptIds;
		if (n.slot == null && applied == null) {
			@:privateAccess n.themePseudo(null, null);
			return;
		}
		if (baseIndex == null) baseIndex = indexOf(base);
		var ix = sheet != null ? index(sheet) : baseIndex;
		var rules = n.slot == null ? null : ix.get(n.slot) ?? ix.get("*");
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
				if (r.conds != null)
					for (c in r.conds)
						if (!holds(n, ui, c)) {
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
			var given = m.ids.indexOf(COLOR);
			current = given >= 0 ? (m.values[given] : Color) : n.style.color != null && !(applied != null && applied.indexOf(COLOR) >= 0) ? n.style.color : n.parent != null ? n.parent.textColor() : Color.BLACK;
			if (current.isToken) current = Color.BLACK;
		}
		// (what it applied: the merge's own arrays while each property is
		// applied as merged, none made; its own from the first that is not)
		var ids:Null<Array<Int>> = null, values:Null<Array<Dynamic>> = null, sharing = true;
		for (i in 0...m.ids.length) {
			var id = m.ids[i], want:Dynamic = m.values[i];
			if (m.current) want = withCurrentAt(id, want, current);
			var cur = n.style.targetAt(id);
			var k = applied == null ? -1 : applied.indexOf(id);
			// (the node's own value: left as it is)
			if ((k >= 0 ? !same(cur, appliedValues[k]) : !same(cur, initialAt(id))) || kept != null && kept.indexOf(id) >= 0) {
				if (sharing) {
					ids = m.ids.slice(0, i);
					values = m.values.slice(0, i);
					sharing = false;
				}
				continue;
			}
			if (!same(cur, want)) StyleFields.setAt(n.style, id, want);
			var v = n.style.targetAt(id);
			if (sharing && !same(v, m.values[i])) {
				ids = m.ids.slice(0, i);
				values = m.values.slice(0, i);
				sharing = false;
			}
			if (!sharing) {
				ids.push(id);
				values.push(v);
			}
		}
		if (sharing) {
			ids = m.ids;
			values = m.values;
		}
		if (ids.length == 0) {
			ids = null;
			values = null;
		}
		// (what the rules wrote and no longer set, still as they wrote it: back to the default)
		if (applied != null)
			for (k in 0...applied.length) {
				var id = applied[k];
				if ((ids == null || ids.indexOf(id) < 0) && same(n.style.targetAt(id), appliedValues[k]))
					StyleFields.setAt(n.style, id, initialAt(id));
			}
		@:privateAccess n.themedIds = ids;
		@:privateAccess n.themedValues = values;
		@:privateAccess n.themePseudo(m.placeholder == null ? null : colorWithCurrent(m.placeholder, current),
			m.selection == null ? null : colorWithCurrent(m.selection, current));
	}

	// (a merge: the properties it sets and their values, tokens resolved but
	// currentColor, which a node resolves; its placeholder's colour, its
	// selection's: the "placeholder" rules' color, the "selection" rules' background)
	static final NONE = new Merge([], [], null, null, false);
	static final merges = new Map<String, Merge>();
	static final sheetIds = new haxe.ds.ObjectMap<{}, Int>();

	static function sheetId(sheet:StyleSheet):Int {
		var id = sheetIds.get(sheet);
		if (id == null) sheetIds.set(sheet, id = Lambda.count(sheetIds) + 1);
		return id;
	}

	static function merged(key:String, rules:Array<Indexed>, sheet:Null<StyleSheet>, dark:Bool):Merge {
		var m = merges.get(key);
		if (m != null) return m;
		var tokens = sheet == null ? null : dark && sheet.dark != null ? sheet.dark : sheet.light;
		var scratch = new Node().style, placeholder:Null<Color> = null, selection:Null<Color> = null;
		var parts = key.split(",");
		for (k in 1...parts.length) {
			var r = rules[Std.parseInt(parts[k])], style = r.rule.style;
			if (r.rule.when != null && r.rule.when.indexOf("placeholder") >= 0) {
				if (style.color != null) placeholder = style.color;
			} else if (r.rule.when != null && r.rule.when.indexOf("selection") >= 0) {
				if (style.background != null) selection = style.background;
			} else {
				// (corners or borders some of whose sides a rule leaves (NaN): those before it kept, as CSS's longhands)
				var c = style.corners, b = style.borders;
				var cBefore = c != null && partial([c.topLeft, c.topRight, c.bottomRight, c.bottomLeft]) ? scratch.corners ?? new Corners(scratch.radius, scratch.radius, scratch.radius, scratch.radius) : null;
				var bBefore = b != null && partial([b.top, b.right, b.bottom, b.left]) ? scratch.borders ?? new Edges(scratch.borderWidth, scratch.borderWidth, scratch.borderWidth, scratch.borderWidth) : null;
				scratch.set(style);
				if (cBefore != null)
					scratch.corners = new Corners(or(c.topLeft, cBefore.topLeft), or(c.topRight, cBefore.topRight), or(c.bottomRight, cBefore.bottomRight), or(c.bottomLeft, cBefore.bottomLeft));
				if (bBefore != null)
					scratch.borders = new Edges(or(b.top, bBefore.top), or(b.right, bBefore.right), or(b.bottom, bBefore.bottom), or(b.left, bBefore.left));
			}
		}
		resolveColors(scratch, tokens, CURRENT, dark);
		// (lengths naming the sheet's: radii, one corner's)
		var lengths = sheet == null ? null : sheet.lengths;
		if (Length.isToken(scratch.radius)) scratch.radius = Math.max(0, Length.resolve(scratch.radius, lengths));
		var cr = scratch.corners;
		if (cr != null && (Length.isToken(cr.topLeft) || Length.isToken(cr.topRight) || Length.isToken(cr.bottomRight) || Length.isToken(cr.bottomLeft)))
			scratch.corners = new Corners(Length.resolve(cr.topLeft, lengths), Length.resolve(cr.topRight, lengths), Length.resolve(cr.bottomRight, lengths),
				Length.resolve(cr.bottomLeft, lengths));
		var ids = [], values:Array<Dynamic> = [], current = false;
		for (id in 0...StyleFields.NAMES.length) {
			var v = StyleFields.getAt(scratch, id);
			if (same(v, initialAt(id))) continue;
			ids.push(id);
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
		m = new Merge(ids, values, placeholder, selection, current);
		merges.set(key, m);
		return m;
	}

	static function partial(sides:Array<Float>):Bool
		return Lambda.exists(sides, Math.isNaN);

	static inline function or(v:Float, before:Float):Float
		return Math.isNaN(v) ? before : v;

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

	// (by id: what each property is, a colour (1), a shadow (2), else 0; color's id)
	static final KINDS = [
		for (name in StyleFields.NAMES)
			COLORS.indexOf(name) >= 0 ? 1 : name == "shadow" || name == "textShadow" ? 2 : 0
	];
	static final COLOR = StyleFields.NAMES.indexOf("color");

	// (a value with currentColor, a token's alpha kept, as a node's colour)
	static function withCurrentAt(id:Int, v:Dynamic, current:Color):Dynamic {
		if (v == null) return v;
		return switch KINDS[id] {
			case 1: colorWithCurrent(v, current);
			case 2 if (shadowUsesCurrent(v)): resolveShadow(v, null, current);
			case _: v;
		}
	}

	static function colorWithCurrent(c:Color, current:Color):Color
		return c.isToken ? current.fade(c.tokenAlpha()) : c;

	// restyles n and its subtree (at the next update)
	public static function restyleTree(n:Node) {
		@:privateAccess n.restyleLater();
		for (c in n.children)
			restyleTree(c);
	}

	// whether a state holds for n (a rule's state, parsed once: Cond)
	static function holds(n:Node, ui:Ui, c:Cond):Bool {
		return switch c.kind {
			case Cond.HOVER: n.hovered;
			case Cond.ACTIVE: n.pressed;
			case Cond.FOCUS: n.focused;
			case Cond.FOCUS_VISIBLE: n.focused && ui.focusVisible;
			case Cond.DISABLED: n.attr("disabled") != null || n.attr("data-disabled") != null;
			case Cond.DARK: ui.dark;
			case Cond.RTL: n.rtl();
			case Cond.WIDE: ui.width >= c.width;
			case Cond.STARTING:
				// (CSS's @starting-style: until its first draw; then again, its transition easing from these)
				@:privateAccess n.style.starting = true;
				!@:privateAccess n.style.drawn;
			case Cond.LTR: !n.rtl();
			case Cond.FIRST: n.parent != null && n.parent.children[0] == n;
			case Cond.LAST: n.parent != null && n.parent.children[n.parent.children.length - 1] == n;
			case Cond.SVG: n is ImageNode && (cast n : ImageNode).svg != null;
			case Cond.NOT: !holds(n, ui, c.inner);
			case Cond.PARENT: n.parent != null && holds(n.parent, ui, c.inner);
			case Cond.PREV:
				var i = n.parent == null ? -1 : n.parent.indexOf(n);
				while (--i >= 0 && marker(n.parent.children[i])) {}
				i >= 0 && all(n.parent.children[i], ui, c.all);
			case Cond.GROUP:
				var p = n.parent;
				while (p != null && !(marked(p, "group", c.name) && holds(p, ui, c.inner)))
					p = p.parent;
				p != null;
			case Cond.PEER:
				var found = false;
				if (n.parent != null)
					for (k in n.parent.children) {
						if (k == n) break;
						if (marked(k, "peer", c.name) && holds(k, ui, c.inner)) {
							found = true;
							break;
						}
					}
				found;
			case Cond.HAS_CHILD: Lambda.exists(n.children, k -> all(k, ui, c.all));
			case Cond.HAS: below(n, ui, c.all);
			case Cond.SLOTTED: n.slot != null;
			case Cond.SLOT: n.slot == c.value;
			case Cond.VARIANT: n.variant == c.value;
			case Cond.SIZE: n.size == c.value;
			case Cond.ATTR: c.value == null ? n.attr(c.name) != null : n.attr(c.name) == c.value;
			case _: false;
		}
	}

	// (a view's marker, where content goes: hidden, of no slot or children; no sibling for prev:)
	static inline function marker(n:Node):Bool
		return n.style.display == None && n.slot == null && n.children.length == 0;

	// (the sibling from i on that is no marker, restyled: its prev: rules may follow)
	static function after(parent:Node, i:Int) {
		while (i >= 0 && i < parent.children.length && marker(parent.children[i]))
			i++;
		if (i >= 0 && i < parent.children.length) touched(parent.children[i]);
	}

	// (whether n is marked as a group or peer: the attribute, else its slot's
	// marker in its sheet (StyleSheet.markers), naming name when given)
	static function marked(n:Node, attr:String, name:Null<String>):Bool {
		var v = n.attr(attr);
		if (v != null) return name == null || v.split(" ").indexOf(name) >= 0;
		if (n.slot == null) return false;
		var sheet = n.sheet();
		if (sheet == null || sheet.markers == null) return false;
		var m = slotMarkers.get(sheet);
		if (m == null) {
			// (each slot's names per marker: "group" => ["", "item"], "" an unnamed one)
			m = new Map();
			for (slot => list in sheet.markers) {
				var by = new Map<String, Array<String>>();
				for (w in list.split(" ")) {
					var slash = w.indexOf("/"), kind = slash < 0 ? w : w.substr(0, slash);
					if (!by.exists(kind)) by.set(kind, []);
					by.get(kind).push(slash < 0 ? "" : w.substr(slash + 1));
				}
				m.set(slot, by);
			}
			slotMarkers.set(sheet, m);
		}
		var by = m.get(n.slot), names = by == null ? null : by.get(attr);
		return names != null && (name == null || names.indexOf(name) >= 0);
	}

	// (the sheets' slots' markers, read once: Rules.marked)
	static final slotMarkers = new haxe.ds.ObjectMap<{}, Map<String, Map<String, Array<String>>>>();

	// (whether a descendant of n holds each of cs)
	static function below(n:Node, ui:Ui, cs:Array<Cond>):Bool {
		for (k in n.children)
			if (all(k, ui, cs) || below(k, ui, cs)) return true;
		return false;
	}

	// (whether n holds each of cs: a has:'s or prev:'s states, "&" between them)
	static function all(n:Node, ui:Ui, cs:Array<Cond>):Bool {
		for (c in cs)
			if (!holds(n, ui, c)) return false;
		return true;
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
			if (head == "parent") r |= PARENT;
			if (head == "prev") r |= PREV;
			var inner = relations(w.substr(colon + 1));
			if (r & (GROUP | PEER | HAS | PARENT | PREV) != 0 && inner & (GROUP | PEER | HAS | PARENT | PREV) != 0) r |= NESTED;
			r |= inner;
		}
		return r;
	}

	// (n's states or attributes changed: the nodes whose rules over other nodes' states may follow, restyled)
	@:allow(hxmc.ui.Node) @:allow(hxmc.ui.Ui) static function related(n:Node) {
		if (relational == 0 || n.ui == null) return;
		if (relational & GROUP != 0 && marked(n, "group", null))
			for (c in n.children)
				restyleTree(c);
		if (relational & PARENT != 0)
			for (c in n.children)
				touched(c);
		if (relational & PREV != 0 && n.parent != null) after(n.parent, n.parent.indexOf(n) + 1);
		if (relational & PEER != 0 && marked(n, "peer", null) && n.parent != null) {
			var after = false;
			for (c in n.parent.children) {
				if (after) restyleTree(c);
				if (c == n) after = true;
			}
		}
		if (relational & HAS != 0) {
			var p = n.parent;
			while (p != null) {
				touched(p);
				p = p.parent;
			}
		}
	}

	// (n's slot changed: what other nodes' rules read of it ("has:>data-slot=x"),
	// and what a marker its slot had or has now (StyleSheet.markers) styled)
	@:allow(hxmc.ui.Node) static function reslotted(n:Node) {
		related(n);
		if (relational & (GROUP | PEER) != 0 && n.ui != null && n.parent != null) restyleTree(n.parent);
	}

	// (m's state as other nodes' rules read it may have changed: m restyled,
	// and with a relation within one ("group:has:x") the nodes reading it
	// through theirs: as a group its descendants, as a peer its later
	// siblings', the sibling after it and its children)
	static function touched(m:Node) {
		@:privateAccess m.restyleLater();
		if (relational & NESTED == 0) return;
		if (marked(m, "group", null))
			for (c in m.children)
				restyleTree(c);
		var p = m.parent;
		if (p != null) {
			if (marked(m, "peer", null)) {
				var later = false;
				for (c in p.children) {
					if (later) restyleTree(c);
					if (c == m) later = true;
				}
			}
			var i = p.indexOf(m) + 1;
			while (i < p.children.length && marker(p.children[i]))
				i++;
			if (i < p.children.length) @:privateAccess p.children[i].restyleLater();
		}
		for (c in m.children)
			@:privateAccess c.restyleLater();
	}

	// (parent's children changed, child put in or taken out, first and last
	// maybe others, next the child after where it was or is: theirs, the
	// peers' siblings', and the ancestors' has rules, restyled)
	@:allow(hxmc.ui.Node) static function placed(parent:Node, child:Null<Node>, first:Null<Node>, last:Null<Node>, ?next:Node) {
		if (relational == 0 || parent.ui == null) return;
		if (relational & PREV != 0) {
			if (next != null) after(parent, parent.indexOf(next));
			if (child == null) for (c in parent.children) @:privateAccess c.restyleLater();
		}
		if (relational & PLACE != 0) {
			if (first != null) @:privateAccess first.restyleLater();
			if (last != null) @:privateAccess last.restyleLater();
			var c = parent.children;
			if (c.length > 0) {
				@:privateAccess c[0].restyleLater();
				@:privateAccess c[c.length - 1].restyleLater();
			}
		}
		if (relational & PEER != 0 && (child == null ? Lambda.exists(parent.children, c -> marked(c, "peer", null)) : marked(child, "peer", null)))
			for (c in parent.children)
				restyleTree(c);
		if (relational & HAS != 0) {
			var p = parent;
			while (p != null) {
				touched(p);
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

	static inline function initialAt(id:Int):Dynamic {
		if (fresh == null) fresh = new Node().style;
		return StyleFields.getAt(fresh, id);
	}

	// (each sheet's rules by slot, in their order; made when a sheet is first used)
	static final indexes = new haxe.ds.ObjectMap<{}, Map<String, Array<Indexed>>>();

	static function index(sheet:StyleSheet):Map<String, Array<Indexed>> {
		var m = indexes.get(sheet);
		if (m != null) return m;
		m = indexOf(sheet.rules);
		indexes.set(sheet, m);
		return m;
	}

	static function indexOf(rules:Array<Rule>):Map<String, Array<Indexed>> {
		var m = new Map<String, Array<Indexed>>();
		for (r in rules) {
			if (r.when != null)
				for (w in r.when)
					relational |= relations(w);
			var l = m.get(r.slot);
			if (l == null) m.set(r.slot, l = []);
			l.push(new Indexed(r));
		}
		// (any slot's, "*": after each slot's own)
		var any = m.get("*");
		if (any != null)
			for (k => l in m)
				if (k != "*") for (r in any) l.push(r);
		return m;
	}
}

// (a merge of rules: Rules.merged)
private class Merge {
	public final ids:Array<Int>;
	public final values:Array<Dynamic>;
	public final placeholder:Null<Color>;
	public final selection:Null<Color>;
	public final current:Bool;

	public function new(ids, values, placeholder, selection, current) {
		this.ids = ids;
		this.values = values;
		this.placeholder = placeholder;
		this.selection = selection;
		this.current = current;
	}
}

// (a rule as indexed: its fields read at each restyle, a class's)
private class Indexed {
	public final variant:Null<String>;
	public final size:Null<String>;
	// (its states parsed, the pseudo-elements' left out: null, none)
	public final conds:Null<Array<Cond>>;
	public final rule:Rule;

	public function new(r:Rule) {
		variant = r.variant;
		size = r.size;
		var cs = r.when == null ? [] : [for (w in r.when) if (w != "placeholder" && w != "selection") Cond.of(w)];
		conds = cs.length == 0 ? null : cs;
		rule = r;
	}
}

// (a rule's state parsed once (Rules.holds): its kind, and an attribute's
// name and value, a breakpoint's width, a relation's inner state or states)
private class Cond {
	public static inline var NEVER = 0;
	public static inline var HOVER = 1;
	public static inline var ACTIVE = 2;
	public static inline var FOCUS = 3;
	public static inline var FOCUS_VISIBLE = 4;
	public static inline var DISABLED = 5;
	public static inline var DARK = 6;
	public static inline var RTL = 7;
	public static inline var WIDE = 8;
	public static inline var STARTING = 9;
	public static inline var LTR = 10;
	public static inline var FIRST = 11;
	public static inline var LAST = 12;
	public static inline var SVG = 13;
	public static inline var NOT = 14;
	public static inline var PARENT = 15;
	public static inline var PREV = 16;
	public static inline var GROUP = 17;
	public static inline var PEER = 18;
	public static inline var HAS_CHILD = 19;
	public static inline var HAS = 20;
	public static inline var SLOTTED = 21;
	public static inline var SLOT = 22;
	public static inline var VARIANT = 23;
	public static inline var SIZE = 24;
	public static inline var ATTR = 25;

	public var kind = NEVER;
	public var name:Null<String> = null;
	public var value:Null<String> = null;
	public var width = 0.0;
	public var inner:Null<Cond> = null;
	public var all:Null<Array<Cond>> = null;

	function new() {}

	static final parsed = new Map<String, Cond>();

	// (a state as Rules writes it: "hover", "parent:data-slot=x", "has:>a&b"...)
	public static function of(w:String):Cond {
		var c = parsed.get(w);
		if (c != null) return c;
		c = new Cond();
		parsed.set(w, c);
		c.kind = switch w {
			case "hover": HOVER;
			case "active": ACTIVE;
			case "focus": FOCUS;
			case "focus-visible": FOCUS_VISIBLE;
			case "disabled": DISABLED;
			case "dark": DARK;
			case "rtl": RTL;
			case "starting": STARTING;
			case "ltr": LTR;
			case "first": FIRST;
			case "last": LAST;
			case "svg": SVG;
			case "sm" | "md" | "lg" | "xl" | "2xl":
				c.width = Ui.BREAKPOINTS.get(w);
				WIDE;
			case _: NEVER;
		}
		if (c.kind != NEVER) return c;
		var colon = w.indexOf(":");
		if (colon > 0) {
			var head = w.substr(0, colon), inner = w.substr(colon + 1);
			var slash = head.indexOf("/");
			if (slash >= 0) {
				c.name = head.substr(slash + 1);
				head = head.substr(0, slash);
			}
			inline function list(s:String):Array<Cond>
				return [for (p in s.split("&")) of(p)];
			switch head {
				case "not" | "parent" | "group" | "peer":
					c.kind = head == "not" ? NOT : head == "parent" ? PARENT : head == "group" ? GROUP : PEER;
					c.inner = of(inner);
				case "prev":
					c.kind = PREV;
					c.all = list(inner);
				case "has":
					var child = StringTools.startsWith(inner, ">");
					c.kind = child ? HAS_CHILD : HAS;
					c.all = list(child ? inner.substr(1) : inner);
				case _:
			}
			return c;
		}
		var eq = w.indexOf("=");
		if (eq < 0) {
			if (w == "data-slot") c.kind = SLOTTED else {
				c.kind = ATTR;
				c.name = w;
			}
			return c;
		}
		var key = w.substr(0, eq);
		c.value = w.substr(eq + 1);
		switch key {
			case "data-slot": c.kind = SLOT;
			case "variant": c.kind = VARIANT;
			case "size": c.kind = SIZE;
			case _:
				c.kind = ATTR;
				c.name = key;
		}
		return c;
	}
}
