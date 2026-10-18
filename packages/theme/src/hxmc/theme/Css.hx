package hxmc.theme;

using StringTools;

// a CSS rule as Css makes it: at-rules around it (outermost first), its
// selector (& for the element the class is on), its declarations
typedef CssRule = {at:Array<String>, sel:String, decls:Array<Array<String>>};

// Tailwind v4's class lists as CSS, for the DOM (packages/web's widgets):
// the same class lists Tw turns into hxmc.ui's rules (shadcn.json, its
// include extras.json, or a sheet of one's own in that format), each class
// as the CSS Tailwind writes for it (test/tailwind.txt holds Tailwind's own
// for every class the sheet has, which CssTest compares), its selector the
// slot's instead of the class's: [data-slot=button], a cva variant or size
// as :where([data-variant=outline]) (as specific as the class it stands
// for), groups and peers as the slots whose class lists mark them
// (group/tabs: [data-slot=tabs]). The rules of a slot are grouped by
// selector and ordered as Tailwind orders its CSS (by their variants), a
// variant's or size's after the base's, as cn's tailwind-merge keeps the
// later; theme values written as values (calc(var(--spacing) * 4) as 1rem).
// What Tailwind's preflight and shadcn's globals.css add: the tokens, light
// (:root) and dark (.dark, or the system's unless .light), border colours.
// tw-animate-css's enter animations as transitions from @starting-style;
// its exit animations are left out, as Tw leaves them.
//   Css.sheet("shadcn.json") (at compile time: a string), Css.write
class Css {
	// the theme values Tailwind's classes name (shadcn's on Tailwind's)
	static final THEME = [
		"--spacing" => "0.25rem", "--text-xs" => "0.75rem", "--text-xs--line-height" => "calc(1 / 0.75)", "--text-sm" => "0.875rem",
		"--text-sm--line-height" => "calc(1.25 / 0.875)", "--text-base" => "1rem", "--text-base--line-height" => "calc(1.5 / 1)",
		"--text-lg" => "1.125rem", "--text-lg--line-height" => "calc(1.75 / 1.125)", "--text-xl" => "1.25rem",
		"--text-xl--line-height" => "calc(1.75 / 1.25)", "--text-2xl" => "1.5rem", "--text-2xl--line-height" => "calc(2 / 1.5)", "--text-3xl" => "1.875rem",
		"--text-3xl--line-height" => "calc(2.25 / 1.875)",
		"--font-weight-normal" => "400", "--font-weight-medium" => "500", "--font-weight-semibold" => "600", "--font-weight-bold" => "700",
		"--tracking-tight" => "-0.025em", "--tracking-widest" => "0.1em", "--leading-normal" => "1.5", "--leading-relaxed" => "1.625",
		"--leading-tight" => "1.25", "--leading-snug" => "1.375", "--radius-xs" => "0.125rem", "--ease-in-out" => "cubic-bezier(0.4, 0, 0.2, 1)",
		"--ease-in" => "cubic-bezier(0.4, 0, 1, 1)", "--ease-out" => "cubic-bezier(0, 0, 0.2, 1)", "--animate-spin" => "spin 1s linear infinite",
		"--animate-pulse" => "pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite", "--default-transition-duration" => "150ms",
		"--default-transition-timing-function" => "cubic-bezier(0.4, 0, 0.2, 1)", "--color-white" => "#fff", "--color-black" => "#000",
		"--container-xs" => "20rem", "--container-sm" => "24rem", "--container-md" => "28rem", "--container-lg" => "32rem",
		"--container-xl" => "36rem", "--container-2xl" => "42rem", "--font-sans" => "Inter, ui-sans-serif, system-ui, sans-serif",
		"--font-mono" => "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace"
	];
	static final SHADOWS = [
		"2xs" => "0 1px var(--tw-shadow-color, rgb(0 0 0 / 0.05))", "xs" => "0 1px 2px 0 var(--tw-shadow-color, rgb(0 0 0 / 0.05))",
		"sm" => "0 1px 3px 0 var(--tw-shadow-color, rgb(0 0 0 / 0.1)), 0 1px 2px -1px var(--tw-shadow-color, rgb(0 0 0 / 0.1))",
		"md" => "0 4px 6px -1px var(--tw-shadow-color, rgb(0 0 0 / 0.1)), 0 2px 4px -2px var(--tw-shadow-color, rgb(0 0 0 / 0.1))",
		"lg" => "0 10px 15px -3px var(--tw-shadow-color, rgb(0 0 0 / 0.1)), 0 4px 6px -4px var(--tw-shadow-color, rgb(0 0 0 / 0.1))",
		"xl" => "0 20px 25px -5px var(--tw-shadow-color, rgb(0 0 0 / 0.1)), 0 8px 10px -6px var(--tw-shadow-color, rgb(0 0 0 / 0.1))",
		"2xl" => "0 25px 50px -12px var(--tw-shadow-color, rgb(0 0 0 / 0.25))"
	];
	static final RADII = [
		"xs" => "var(--radius-xs)", "sm" => "calc(var(--radius) * 0.6)", "md" => "calc(var(--radius) * 0.8)", "lg" => "var(--radius)",
		"xl" => "calc(var(--radius) * 1.4)", "2xl" => "calc(var(--radius) * 1.8)", "3xl" => "calc(var(--radius) * 2.2)", "4xl" => "calc(var(--radius) * 2.6)",
		"none" => "0", "full" => "calc(infinity * 1px)"
	];
	static final RADIUS_SIDES = [
		"t" => ["top-left", "top-right"], "r" => ["top-right", "bottom-right"], "b" => ["bottom-right", "bottom-left"],
		"l" => ["top-left", "bottom-left"], "tl" => ["top-left"], "tr" => ["top-right"], "br" => ["bottom-right"], "bl" => ["bottom-left"],
		"s" => ["start-start", "end-start"], "e" => ["start-end", "end-end"]
	];
	static final SIDES = [
		"" => "", "x" => "-inline", "y" => "-block", "t" => "-top", "r" => "-right", "b" => "-bottom", "l" => "-left", "s" => "-inline-start",
		"e" => "-inline-end"
	];
	static final BREAKPOINTS = ["sm" => "40rem", "md" => "48rem", "lg" => "64rem", "xl" => "80rem", "2xl" => "96rem"];
	static final TRANSITIONS = [
		"" => "color, background-color, border-color, outline-color, text-decoration-color, fill, stroke, --tw-gradient-from, --tw-gradient-via, --tw-gradient-to, opacity, box-shadow, transform, translate, scale, rotate, filter, -webkit-backdrop-filter, backdrop-filter, display, content-visibility, overlay, pointer-events",
		"all" => "all",
		"colors" => "color, background-color, border-color, outline-color, text-decoration-color, fill, stroke, --tw-gradient-from, --tw-gradient-via, --tw-gradient-to",
		"opacity" => "opacity", "shadow" => "box-shadow", "transform" => "transform, translate, scale, rotate"
	];
	static final BOX_SHADOW = "var(--tw-inset-shadow), var(--tw-inset-ring-shadow), var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow)";
	// (the keyframes animate-* names)
	static final KEYFRAMES = [
		"spin" => "@keyframes spin{to{transform:rotate(360deg)}}", "pulse" => "@keyframes pulse{50%{opacity:.5}}",
		"caret-blink" => "@keyframes caret-blink{0%,70%,100%{opacity:1}20%,50%{opacity:0}}"
	];
	// utilities with nothing to say in CSS: markers (group, peer), handled as the slots that carry them
	static final MARKERS = ["group", "peer"];

	// a class (its variants and utility) as Tailwind's CSS, & for its element
	// (null: unknown); group and peer markers map a marker ("group/tabs",
	// "peer") to the selector of the elements that carry it, attr a
	// [class*=x] test to the selector of the elements whose classes hold x
	public static function rules(c:String, ?groups:String->String, ?attr:String->String):Null<Array<CssRule>> {
		var parts = Tailwind.splitVariants(c);
		var utility = parts.pop();
		var important = false;
		if (utility.endsWith("!")) {
			important = true;
			utility = utility.substr(0, utility.length - 1);
		} else if (utility.startsWith("!")) {
			important = true;
			utility = utility.substr(1);
		}
		var out = utilityRules(utility);
		if (out == null) return null;
		if (important) for (r in out)
			r.decls = [for (d in r.decls) [d[0], d[1] + " !important"]];
		groups = groups ?? (m -> ":where(." + escape(m) + ")");
		attr = attr ?? (a -> a);
		// (left to right: each wraps or extends the selector so far; the first's at-rule outermost)
		for (v in parts)
			if (v == "selection") {
				// (the element's text and its descendants', two rules)
				out = [for (r in out) for (k in 0...2) {at: r.at.copy(), sel: r.sel + (k == 0 ? " ::selection" : "::selection"), decls: r.decls}];
			} else for (r in out)
				if (!variant(v, r, groups, attr)) return null;
		return out;
	}

	// a class list as CSS for the elements a selector picks (an instance's
	// classes of its own: Css.classes("#search [data-slot=command]",
	// "rounded-lg border shadow-md"), one rule per class, in its order
	public static function classes(selector:String, list:String):String {
		var out = new StringBuf();
		for (c in ~/\s+/g.split(StringTools.trim(list))) {
			var rs = c == "" ? [] : rules(c);
			if (rs == null) throw 'Css: unknown class $c';
			for (r in rs) {
				if (r.decls.length == 0) continue;
				var body = r.sel.replace("&", selector) + "{" + [for (d in r.decls) d[0] + ":" + minify(resolve(d[1]))].join(";") + "}";
				for (i in 0...r.at.length)
					body = r.at[r.at.length - 1 - i] + "{" + body + "}";
				out.add(body + "\n");
			}
		}
		return out.toString();
	}

	// (a class name as a selector writes it)
	static function escape(s:String):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			var ch = s.charCodeAt(i);
			if (!(ch >= "a".code && ch <= "z".code || ch >= "A".code && ch <= "Z".code || ch >= "0".code && ch <= "9".code || ch == "-".code
				|| ch == "_".code)) b.add("\\");
			b.addChar(ch);
		}
		return b.toString();
	}

	// applies a variant to a rule (false: unknown)
	static function variant(v:String, r:CssRule, groups:String->String, attr:String->String):Bool {
		inline function sel(f:String->String)
			r.sel = f(r.sel);
		inline function pseudo(p:String)
			r.sel = r.sel + p;
		switch v {
			case "hover":
				pseudo(":hover");
				r.at.push("@media (hover: hover)");
				return true;
			case "focus" | "focus-visible" | "active" | "disabled" | "enabled" | "checked" | "indeterminate" | "invalid" | "focus-within" | "empty"
				| "read-only" | "required" | "visited" | "target":
				pseudo(":" + v);
				return true;
			case "first" | "last" | "only":
				pseudo(":" + v + "-child");
				return true;
			case "odd":
				pseudo(":nth-child(odd)");
				return true;
			case "even":
				pseudo(":nth-child(even)");
				return true;
			case "open":
				pseudo(":is([open], :popover-open, :open)");
				return true;
			case "placeholder":
				pseudo("::placeholder");
				return true;
			case "file":
				pseudo("::file-selector-button");
				return true;
			case "after" | "before":
				pseudo("::" + v);
				r.decls.unshift(["content", "var(--tw-content)"]);
				return true;
			case "dark":
				pseudo(":is(.dark *)");
				return true;
			case "rtl" | "ltr":
				pseudo(':where(:dir($v), [dir="$v"], [dir="$v"] *)');
				return true;
			case "starting":
				r.at.push("@starting-style");
				return true;
			case "motion-safe" | "motion-reduce":
				r.at.push("@media (prefers-reduced-motion: " + (v == "motion-safe" ? "no-preference" : "reduce") + ")");
				return true;
			case "*":
				sel(s -> ":is(" + s + " > *)");
				return true;
			case "**":
				sel(s -> ":is(" + s + " *)");
				return true;
			case _:
		}
		if (BREAKPOINTS.exists(v)) {
			r.at.push("@media (width >= " + BREAKPOINTS[v] + ")");
			return true;
		}
		if (v.startsWith("max-") && BREAKPOINTS.exists(v.substr(4))) {
			r.at.push("@media (width < " + BREAKPOINTS[v.substr(4)] + ")");
			return true;
		}
		// arbitrary: [&_svg] (_ a space), [a&], [svg] (as &:is(svg))
		if (v.startsWith("[") && v.endsWith("]")) {
			var s = combinators(attrs(v.substring(1, v.length - 1).replace("_", " "), attr)).replace("> *:", "> :");
			// (a list: [&>[role=checkbox],[role=radio]], a part without & under it)
			var list = splitTop(s, ",");
			if (s.startsWith("@")) r.at.push(s) else if (list.length > 1 && s.indexOf("&") >= 0) {
				var parts = [for (p in list) p.indexOf("&") >= 0 ? p : "& " + p];
				sel(x -> [for (p in parts) p.replace("&", x)].join(", "));
			} else if (s.indexOf("&") >= 0) sel(x -> s.replace("&", x)) else pseudo(":is(" + s + ")");
			return true;
		}
		for (prefix in ["group", "peer", "in"])
			if (v.startsWith(prefix + "-")) {
				var inner = v.substr(prefix.length + 1), name = "";
				var slash = inner.lastIndexOf("/");
				if (slash > inner.lastIndexOf("]")) {
					name = inner.substr(slash + 1);
					inner = inner.substr(0, slash);
				}
				var probe:CssRule = {at: [], sel: "&", decls: []};
				if (!variant(inner, probe, groups, attr)) return false;
				var marker = prefix == "in" ? "*" : groups(name == "" ? prefix : prefix + "/" + name);
				var inside = probe.sel.replace("&", marker);
				if (prefix == "in") sel(s -> ":where(" + inside + ") " + s) else sel(s -> s + ":is(" + inside + (prefix == "peer" ? " ~ *" : " *") + ")");
				for (a in probe.at)
					r.at.push(a);
				return true;
			}
		if (v.startsWith("has-") || v.startsWith("not-")) {
			var inner = v.substr(4);
			if (v.startsWith("has-") && inner.startsWith("[")) {
				var s = combinators(attrs(inner.substring(1, inner.length - 1).replace("_", " "), attr));
				pseudo(":has(" + (StringTools.startsWith(StringTools.ltrim(s), ">") || StringTools.startsWith(StringTools.ltrim(s), "+")
					|| StringTools.startsWith(StringTools.ltrim(s), "~") ? s : ":is(" + s + ")") + ")");
				return true;
			}
			var probe:CssRule = {at: [], sel: "&", decls: []};
			if (!variant(inner, probe, groups, attr)) return false;
			if (v.startsWith("has-")) pseudo(":has(" + probe.sel.replace("&", "") + ")") else pseudo(":not(" + probe.sel.replace("&", "*") + ")");
			for (a in probe.at)
				r.at.push(a);
			return true;
		}
		if (v.startsWith("aria-")) {
			var a = v.substr(5);
			pseudo(a.startsWith("[") ? attribute("aria-", a) : '[aria-$a="true"]');
			return true;
		}
		if (v.startsWith("data-")) {
			var a = v.substr(5);
			pseudo(a.startsWith("[") ? attribute("data-", a) : '[data-$a]');
			return true;
		}
		if (v.startsWith("nth-last-") || v.startsWith("nth-")) {
			var last = v.startsWith("nth-last-"), n = v.substr(last ? 9 : 4);
			if (n.startsWith("[")) n = n.substring(1, n.length - 1).replace("_", " ");
			pseudo(last ? ":nth-last-child(" + n + ")" : ":nth-child(" + n + ")");
			return true;
		}
		// (container queries: @md/name, the named container's width)
		if (v.startsWith("@")) {
			var slash = v.indexOf("/"), size = slash < 0 ? v.substr(1) : v.substring(1, slash);
			var width = THEME["--container-" + size];
			if (width == null) return false;
			r.at.push("@container " + (slash < 0 ? "" : v.substr(slash + 1) + " ") + "(width >= " + width + ")");
			return true;
		}
		if (v.startsWith("supports-[")) {
			r.at.push("@supports (" + v.substring(10, v.length - 1).replace("_", " ") + ")");
			return true;
		}
		return false;
	}

	// (a selector's > + ~ spaced as Tailwind writes them, outside brackets)
	static function combinators(s:String):String {
		var out = new StringBuf(), depth = 0;
		for (i in 0...s.length) {
			var ch = s.charAt(i);
			if (ch == "[" || ch == "(") depth++ else if (ch == "]" || ch == ")") depth--;
			if (depth == 0 && (ch == ">" || ch == "+" || ch == "~")) out.add(" " + ch + " ") else out.add(ch);
		}
		var r = out.toString();
		while (r.indexOf("  ") >= 0)
			r = r.replace("  ", " ");
		return r.startsWith(" ") && !s.startsWith(">") && !s.startsWith("+") && !s.startsWith("~") ? r.substr(1) : r;
	}

	// ([state=checked]: [data-state="checked"]; [disabled]: [data-disabled])
	static function attribute(prefix:String, a:String):String {
		var inner = a.substring(1, a.length - 1), eq = inner.indexOf("=");
		if (eq < 0) return '[$prefix$inner]';
		var value = inner.substr(eq + 1);
		if (value.startsWith('"') || value.startsWith("'")) value = value.substring(1, value.length - 1);
		return '[$prefix${inner.substr(0, eq)}="$value"]';
	}

	// (an arbitrary selector's class tests, [class*='size-'], as attr has them)
	static function attrs(s:String, attr:String->String):String {
		var out = new StringBuf(), i = 0;
		while (i < s.length) {
			var j = s.indexOf("[class*=", i);
			if (j < 0) break;
			var k = s.indexOf("]", j);
			out.add(s.substring(i, j));
			var v = s.substring(j + 8, k);
			if (v.startsWith("'") || v.startsWith('"')) v = v.substring(1, v.length - 1);
			var a = attr("[class*='" + v + "']");
			out.add(a);
			i = k + 1;
		}
		out.add(s.substr(i));
		return out.toString();
	}

	// a utility's rules (& alone), Tailwind's declarations
	static function utilityRules(u:String):Null<Array<CssRule>> {
		var d = utility(u);
		if (d == null) return null;
		if (u == "outline-hidden") return [{at: [], sel: "&", decls: d}, {at: ["@media (forced-colors: active)"], sel: "&", decls: [["outline", "2px solid transparent"], ["outline-offset", "2px"]]}];
		// (tw-animate-css's starts: what an enter transition starts from)
		var start = u.startsWith("fade-in") || u.startsWith("zoom-in") || u.startsWith("slide-in-from-") || u.startsWith("spin-in")
			|| u.startsWith("-spin-in");
		return [{at: start ? ["@starting-style"] : [], sel: "&", decls: d}];
	}

	// (an arbitrary value: _ a space, calc's operators spaced as Tailwind spaces them)
	static function arbitrary(v:String):String {
		v = v.replace("_", " ");
		if (v.indexOf("calc(") < 0) return v;
		var out = new StringBuf();
		for (i in 0...v.length) {
			var ch = v.charAt(i);
			if ((ch == "+" || ch == "-" || ch == "*" || ch == "/") && i > 0 && v.charAt(i - 1) != " " && v.charAt(i - 1) != "(" && v.charAt(i - 1) != ","
				&& !(ch == "-" && (v.charAt(i - 1) == "*" || v.charAt(i - 1) == "/"))
				&& !(ch == "-" && isNameChar(v.charCodeAt(i - 1)) && i + 1 < v.length && isNameChar(v.charCodeAt(i + 1)) && !isDigit(v.charCodeAt(i + 1)))) {
				// (inside var(--x-y) a dash is the name's)
				if (inVar(v, i)) out.add(ch) else {
					out.add(" " + ch + " ");
					continue;
				}
			} else out.add(ch);
		}
		return out.toString().replace("  ", " ");
	}

	static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	static inline function isNameChar(c:Int):Bool
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code;

	static function inVar(v:String, i:Int):Bool {
		var open = v.lastIndexOf("var(", i);
		return open >= 0 && v.indexOf(")", open) > i;
	}

	// (a number as Tailwind writes it)
	static function num(s:String):Null<Float> {
		if (s == "" || !~/^[0-9]*\.?[0-9]+$/.match(s)) return null;
		return Std.parseFloat(s);
	}

	// a spacing value: the scale (n: n * --spacing), px, a fraction, full, an arbitrary value or a variable
	static function spacing(v:String, neg:Bool, ?fractions = true, ?words:Map<String, String>):Null<String> {
		var s:Null<String> = null;
		if (words != null && words.exists(v)) s = words[v] else if (v == "px") s = "1px" else if (v == "full") s = "100%" else if (v.startsWith("[")
			&& v.endsWith("]")) s = arbitrary(theme(v.substring(1, v.length - 1))) else if (v.startsWith("(") && v.endsWith(")")) s = "var(" + v.substring(1,
				v.length - 1) + ")" else if (fractions && v.indexOf("/") > 0) {
			var p = v.split("/");
			if (num(p[0]) == null || num(p[1]) == null) return null;
			s = 'calc(${p[0]} / ${p[1]} * 100%)';
		} else {
			var n = num(v);
			if (n == null) return null;
			if (neg) return n == 0 ? "0px" : n == 1 ? "calc(var(--spacing) * -1)" : 'calc(var(--spacing) * -$v)';
			return n == 0 ? "0px" : n == 1 ? "var(--spacing)" : 'calc(var(--spacing) * $v)';
		}
		return neg ? 'calc($s * -1)' : s;
	}

	// a colour: a token, white, black, transparent, current, with /alpha
	static function color(v:String):Null<String> {
		var alpha:Null<String> = null, slash = v.lastIndexOf("/");
		if (slash > 0 && !v.startsWith("[")) {
			alpha = v.substr(slash + 1);
			v = v.substr(0, slash);
			if (num(alpha) == null) return null;
		}
		var c = switch v {
			case "transparent": "transparent";
			case "current": "currentcolor";
			case "white" | "black": 'var(--color-$v)';
			case _ if (Tailwind.TOKENS.contains(v)): 'var(--$v)';
			case _: null;
		}
		if (c == null) return null;
		return alpha == null ? c : 'color-mix(in oklab, $c $alpha%, transparent)';
	}

	// a utility's declarations (null: unknown)
	public static function utility(u:String):Null<Array<Array<String>>> {
		var neg = u.startsWith("-");
		if (neg) u = u.substr(1);
		inline function one(p:String, v:String)
			return [[p, v]];
		function after(p:String):Null<String>
			return u.startsWith(p) ? u.substr(p.length) : null;
		switch u {
			case "flex" | "grid" | "block" | "hidden" | "inline-flex" | "inline-grid" | "inline-block" | "inline" | "contents" | "table":
				return one("display", u == "hidden" ? "none" : u);
			case "absolute" | "relative" | "fixed" | "sticky" | "static": return one("position", u);
			case "visible": return one("visibility", "visible");
			case "invisible": return one("visibility", "hidden");
			case "flex-col": return one("flex-direction", "column");
			case "flex-row": return one("flex-direction", "row");
			case "flex-col-reverse": return one("flex-direction", "column-reverse");
			case "flex-row-reverse": return one("flex-direction", "row-reverse");
			case "flex-wrap": return one("flex-wrap", "wrap");
			case "flex-nowrap": return one("flex-wrap", "nowrap");
			case "flex-1": return one("flex", "1");
			case "flex-none": return one("flex", "none");
			case "flex-auto": return one("flex", "auto");
			case "shrink": return one("flex-shrink", "1");
			case "shrink-0": return one("flex-shrink", "0");
			case "grow": return one("flex-grow", "1");
			case "grow-0": return one("flex-grow", "0");
			case "border-collapse": return one("border-collapse", "collapse");
			case "caption-bottom": return one("caption-side", "bottom");
			case "align-middle": return one("vertical-align", "middle");
			case "field-sizing-content": return one("field-sizing", "content");
			case "aspect-square": return one("aspect-ratio", "1 / 1");
			case "aspect-video": return one("aspect-ratio", "var(--aspect-video)");
			case "touch-none": return one("touch-action", "none");
			case "appearance-none": return one("appearance", "none");
			case "list-none": return one("list-style-type", "none");
			case "order-first": return one("order", "-9999");
			case "order-last": return one("order", "9999");
			case "object-cover" | "object-contain" | "object-fill" | "object-none": return one("object-fit", u.substr(7));
			case "select-none" | "select-text" | "select-all" | "select-auto":
				var s = u.substr(7);
				return [["-webkit-user-select", s], ["user-select", s]];
			case "pointer-events-none" | "pointer-events-auto": return one("pointer-events", u.substr(15));
			case "overflow-hidden" | "overflow-auto" | "overflow-visible" | "overflow-scroll" | "overflow-clip": return one("overflow", u.substr(9));
			case "break-words": return one("overflow-wrap", "break-word");
			case "break-all": return one("word-break", "break-all");
			case "whitespace-nowrap" | "whitespace-normal" | "whitespace-pre" | "whitespace-pre-wrap": return one("white-space", u.substr(11));
			case "text-balance" | "text-wrap" | "text-nowrap" | "text-pretty": return one("text-wrap", u.substr(5));
			case "truncate": return [["overflow", "hidden"], ["text-overflow", "ellipsis"], ["white-space", "nowrap"]];
			case "underline" | "overline" | "line-through": return one("text-decoration-line", u);
			case "no-underline": return one("text-decoration-line", "none");
			case "uppercase" | "lowercase" | "capitalize": return one("text-transform", u);
			case "normal-case": return one("text-transform", "none");
			case "italic": return one("font-style", "italic");
			case "not-italic": return one("font-style", "normal");
			case "tabular-nums": return [["--tw-numeric-spacing", "tabular-nums"], ["font-variant-numeric", "var(--tw-ordinal,) var(--tw-slashed-zero,) var(--tw-numeric-figure,) var(--tw-numeric-spacing,) var(--tw-numeric-fraction,)"]];
			case "text-left" | "text-center" | "text-right" | "text-justify" | "text-start" | "text-end": return one("text-align", u.substr(5));
			case "font-sans": return one("font-family", "var(--font-sans)");
			case "font-mono": return one("font-family", "var(--font-mono)");
			case "sr-only":
				return [["position", "absolute"], ["width", "1px"], ["height", "1px"], ["padding", "0"], ["margin", "-1px"], ["overflow", "hidden"],
					["clip-path", "inset(50%)"], ["white-space", "nowrap"], ["border-width", "0"]];
			case "line-clamp-1" | "line-clamp-2" | "line-clamp-3":
				return [["overflow", "hidden"], ["display", "-webkit-box"], ["-webkit-box-orient", "vertical"], ["-webkit-line-clamp", u.substr(11)]];
			case "border": return [["border-style", "var(--tw-border-style)"], ["border-width", "1px"]];
			case "outline": return [["outline-style", "var(--tw-outline-style)"], ["outline-width", "1px"]];
			case "outline-none" | "outline-hidden": return [["--tw-outline-style", "none"], ["outline-style", "none"]];
			case "ring-inset": return one("--tw-ring-inset", "inset");
			case "shadow-none": return [["--tw-shadow", "0 0 #0000"], ["box-shadow", BOX_SHADOW]];
			case "transition-none": return one("transition-property", "none");
			case "animate-none": return one("animation", "none");
			case "animate-spin" | "animate-pulse": return one("animation", "var(--" + u + ")");
			case "animate-caret-blink": return one("animation", "caret-blink 1.25s ease-out infinite");
			// tw-animate-css's enter: a transition from @starting-style (its
			// fade-in-*, zoom-in-*, slide-in-from-* set what it starts from)
			case "animate-in":
				return one("transition", "opacity var(--tw-duration, 150ms) var(--tw-ease, ease), translate var(--tw-duration, 150ms) var(--tw-ease, ease), scale var(--tw-duration, 150ms) var(--tw-ease, ease), rotate var(--tw-duration, 150ms) var(--tw-ease, ease)");
			case "@container": return one("container-type", "inline-size");
			case "mx-auto": return one("margin-inline", "auto");
			case _:
		}
		var v:Null<String>;
		if ((v = after("@container/")) != null) return [["container-type", "inline-size"], ["container-name", v]];
		// arbitrary properties: [--cell-size:--spacing(8)]
		if (u.startsWith("[") && u.endsWith("]") && u.indexOf(":") > 0) {
			var inner = u.substring(1, u.length - 1), colon = inner.indexOf(":");
			return one(inner.substr(0, colon), theme(arbitrary(inner.substr(colon + 1))));
		}
		// tw-animate-css's starts (with animate-in, in @starting-style)
		if ((v = after("fade-in")) != null) return one("opacity", v == "" ? "0" : '${Std.parseFloat(v.substr(1)) / 100}');
		if ((v = after("zoom-in")) != null) return one("scale", v == "" ? "0" : '${Std.parseFloat(v.substr(1)) / 100}');
		if ((v = after("spin-in")) != null) return one("rotate", v == "" ? "30deg" : (neg ? "-" : "") + v.substr(1) + "deg");
		if ((v = after("slide-in-from-")) != null) {
			var dash = v.indexOf("-"), side = dash < 0 ? v : v.substr(0, dash), amount = dash < 0 ? "100%" : spacing(v.substr(dash + 1), false);
			if (amount == null) return null;
			return switch side {
				case "top": one("translate", '0 calc($amount * -1)');
				case "bottom": one("translate", '0 $amount');
				case "left" | "start": one("translate", 'calc($amount * -1) 0');
				case "right" | "end": one("translate", '$amount 0');
				case _: null;
			}
		}
		if (u.startsWith("animate-out") || u.startsWith("fade-out") || u.startsWith("zoom-out") || u.startsWith("slide-out-to-")
			|| u.startsWith("spin-out") || u.startsWith("animate-accordion-")) return [];
		if (MARKERS.contains(u) || u.startsWith("group/") || u.startsWith("peer/")) return [];
		// position
		for (p in [["inset-x-", "inset-inline"], ["inset-y-", "inset-block"], ["inset-", "inset"], ["top-", "top"], ["right-", "right"],
			["bottom-", "bottom"], ["left-", "left"], ["start-", "inset-inline-start"], ["end-", "inset-inline-end"]])
			if ((v = after(p[0])) != null) {
				var s = spacing(v, neg, true, ["auto" => "auto"]);
				return s == null ? null : one(p[1], s);
			}
		if ((v = after("z-")) != null) return one("z-index", neg ? "calc(" + v + " * -1)" : v);
		if ((v = after("order-")) != null) return one("order", v);
		for (p in [["col-start-", "grid-column-start"], ["col-end-", "grid-column-end"], ["row-start-", "grid-row-start"], ["row-end-", "grid-row-end"]])
			if ((v = after(p[0])) != null) return one(p[1], v);
		if ((v = after("col-span-")) != null) return one("grid-column", v == "full" ? "1 / -1" : 'span $v / span $v');
		if ((v = after("row-span-")) != null) return one("grid-row", v == "full" ? "1 / -1" : 'span $v / span $v');
		// spacing
		for (p in ["p", "m"])
			for (side in ["", "x", "y", "t", "r", "b", "l", "s", "e"])
				if ((v = after(p + side + "-")) != null) {
					var s = spacing(v, neg, false, p == "m" ? ["auto" => "auto"] : null);
					return s == null ? null : one((p == "p" ? "padding" : "margin") + SIDES[side], s);
				}
		if ((v = after("scroll-my-")) != null) return one("scroll-margin-block", spacing(v, neg, false));
		if ((v = after("scroll-py-")) != null) return one("scroll-padding-block", spacing(v, neg, false));
		for (p in [["gap-x-", "column-gap"], ["gap-y-", "row-gap"], ["gap-", "gap"]])
			if ((v = after(p[0])) != null) {
				var s = v.startsWith("[--spacing(") ? 'calc(var(--spacing) * ${v.substring(11, v.length - 2)})' : spacing(v, false, false);
				return s == null ? null : one(p[1], s);
			}
		// sizes
		var sizeWords = [
			"auto" => "auto", "fit" => "fit-content", "min" => "min-content", "max" => "max-content", "screen" => "100vw", "dvh" => "100dvh", "svh" => "100svh", "lvh" => "100lvh"
		];
		for (p in [["size-", "size"], ["min-w-", "min-width"], ["max-w-", "max-width"], ["min-h-", "min-height"], ["max-h-", "max-height"],
			["w-", "width"], ["h-", "height"]])
			if ((v = after(p[0])) != null) {
				var s = p[1] == "max-width" && THEME.exists("--container-" + v) ? 'var(--container-$v)' : spacing(v, neg, true, sizeWords);
				if (p[1] == "height" && v == "screen") s = "100vh";
				if (s == null) return null;
				return p[1] == "size" ? [["width", s], ["height", s]] : one(p[1], s);
			}
		if ((v = after("basis-")) != null) {
			var s = spacing(v, false, true, sizeWords);
			return s == null ? null : one("flex-basis", s);
		}
		// flex and grid
		for (p in [["items-", "align-items"], ["self-", "align-self"], ["content-", "align-content"]])
			if ((v = after(p[0])) != null) return one(p[1], v == "start" ? "flex-start" : v == "end" ? "flex-end" : v);
		if ((v = after("justify-items-")) != null) return one("justify-items", v);
		if ((v = after("justify-self-")) != null) return one("justify-self", v == "start" ? "flex-start" : v == "end" ? "flex-end" : v);
		if ((v = after("justify-")) != null)
			return one("justify-content", switch v {
				case "start": "flex-start";
				case "end": "flex-end";
				case "between" | "around" | "evenly": "space-" + v;
				case _: v;
			});
		if ((v = after("place-content-")) != null) return one("place-content", v);
		if ((v = after("place-items-")) != null) return one("place-items", v);
		if ((v = after("auto-rows-")) != null) return one("grid-auto-rows", v == "min" ? "min-content" : v == "max" ? "max-content" : v == "fr" ? "minmax(0, 1fr)" : v);
		for (p in [["grid-cols-", "grid-template-columns"], ["grid-rows-", "grid-template-rows"]])
			if ((v = after(p[0])) != null) {
				if (v.startsWith("[")) return one(p[1], arbitrary(v.substring(1, v.length - 1)));
				if (num(v) == null) return v == "none" ? one(p[1], "none") : null;
				return one(p[1], 'repeat($v, minmax(0, 1fr))');
			}
		if ((v = after("overflow-x-")) != null) return one("overflow-x", v);
		if ((v = after("overflow-y-")) != null) return one("overflow-y", v);
		// corners
		if ((v = after("rounded")) != null) {
			var side = "", size = v;
			if (v.startsWith("-")) {
				size = v.substr(1);
				var dash = size.indexOf("-");
				var first = dash < 0 ? size : size.substr(0, dash);
				if (RADIUS_SIDES.exists(first)) {
					side = first;
					size = dash < 0 ? "" : size.substr(dash + 1);
				}
			}
			var r = size == "" ? "0.25rem" : RADII.exists(size) ? RADII[size] : size.startsWith("[") ? arbitrary(size.substring(1, size.length - 1)) : null;
			if (r == null) return null;
			if (side == "") return one("border-radius", r);
			return [for (c in RADIUS_SIDES[side]) ['border-$c-radius', r]];
		}
		// borders
		if ((v = after("border")) != null) {
			var side = "", rest = v;
			for (s in ["x", "y", "t", "r", "b", "l", "s", "e"])
				if (v == "-" + s || v.startsWith("-" + s + "-")) {
					side = s;
					rest = v.substr(2);
				}
			var w = rest == "" ? "1px" : rest.startsWith("-") && num(rest.substr(1)) != null ? rest.substr(1) + "px" : null;
			if (w != null) {
				var p = side == "" ? "border" : "border" + SIDES[side];
				return [['$p-style', "var(--tw-border-style)"], ['$p-width', w]];
			}
			if (rest.startsWith("-")) {
				var c = color(rest.substr(1));
				if (c != null) return one(side == "" ? "border-color" : "border" + SIDES[side] + "-color", c);
			}
			if (side == "" && rest.startsWith("-")) {
				switch rest {
					case "-solid" | "-dashed" | "-dotted" | "-none": return [["--tw-border-style", rest.substr(1)], ["border-style", rest.substr(1)]];
					case _:
				}
			}
			return null;
		}
		// colours
		for (p in [["bg-", "background-color"], ["text-", "color"], ["fill-", "fill"], ["stroke-", "stroke"], ["caret-", "caret-color"],
			["accent-", "accent-color"], ["decoration-", "text-decoration-color"], ["outline-", "outline-color"], ["ring-offset-", "--tw-ring-offset-color"],
			["ring-", "--tw-ring-color"], ["shadow-", "--tw-shadow-color"]])
			if ((v = after(p[0])) != null) {
				var c = color(v);
				if (c != null) return one(p[1], c);
			}
		// text sizes and the rest of text
		if ((v = after("text-")) != null) {
			var slash = v.indexOf("/");
			if (slash > 0 && THEME.exists("--text-" + v.substr(0, slash))) {
				var l = v.substr(slash + 1);
				var lh = THEME.exists("--leading-" + l) ? "var(--leading-" + l + ")" : l.startsWith("[") ? arbitrary(l.substring(1, l.length - 1)) : spacing(l, false, false);
				return lh == null ? null : [["font-size", "var(--text-" + v.substr(0, slash) + ")"], ["line-height", lh]];
			}
			if (THEME.exists('--text-$v'))
				return [["font-size", 'var(--text-$v)'], ["line-height", 'var(--tw-leading, var(--text-$v--line-height))']];
			if (v.startsWith("[")) return one("font-size", arbitrary(v.substring(1, v.length - 1)));
			return null;
		}
		if ((v = after("font-")) != null) {
			if (!THEME.exists('--font-weight-$v')) return null;
			return [["--tw-font-weight", 'var(--font-weight-$v)'], ["font-weight", 'var(--font-weight-$v)']];
		}
		if ((v = after("leading-")) != null) {
			var s = v == "none" ? "1" : THEME.exists('--leading-$v') ? 'var(--leading-$v)' : v.startsWith("[") ? arbitrary(v.substring(1, v.length - 1)) : spacing(v, false, false);
			return s == null ? null : [["--tw-leading", s], ["line-height", s]];
		}
		if ((v = after("tracking-")) != null) {
			var s = THEME.exists('--tracking-$v') ? 'var(--tracking-$v)' : v.startsWith("[") ? arbitrary(v.substring(1, v.length - 1)) : null;
			return s == null ? null : [["--tw-tracking", s], ["letter-spacing", s]];
		}
		if ((v = after("underline-offset-")) != null) return one("text-underline-offset", num(v) != null ? v + "px" : v);
		// effects
		if ((v = after("opacity-")) != null) return num(v) == null ? null : one("opacity", v + "%");
		if ((v = after("shadow")) != null) {
			var s = v == "" ? SHADOWS["sm"] : v.startsWith("-[") ? shadowColor(arbitrary(v.substring(2, v.length - 1))) : SHADOWS[v.substr(1)];
			return s == null ? null : [["--tw-shadow", s], ["box-shadow", BOX_SHADOW]];
		}
		if ((v = after("ring-offset-")) != null)
			return num(v) == null ? null : [["--tw-ring-offset-width", v + "px"],
				["--tw-ring-offset-shadow", "var(--tw-ring-inset,) 0 0 0 var(--tw-ring-offset-width) var(--tw-ring-offset-color)"]];
		if ((v = after("ring")) != null) {
			var w = v == "" ? "1px" : num(v.substr(1)) != null ? v.substr(1) + "px" : v.startsWith("-[") ? v.substring(2, v.length - 1) : null;
			if (w == null) return null;
			return [["--tw-ring-shadow", 'var(--tw-ring-inset,) 0 0 0 calc($w + var(--tw-ring-offset-width)) var(--tw-ring-color, currentcolor)'],
				["box-shadow", BOX_SHADOW]];
		}
		if ((v = after("outline-offset-")) != null) return one("outline-offset", num(v) != null ? v + "px" : v);
		if ((v = after("outline-")) != null)
			return num(v) == null ? null : [["outline-style", "var(--tw-outline-style)"], ["outline-width", v + "px"]];
		if ((v = after("cursor-")) != null) return one("cursor", v);
		// transforms
		if ((v = after("origin-")) != null) return one("transform-origin", v.startsWith("(") ? 'var(${v.substring(1, v.length - 1)})' : v.replace("-", " "));
		for (axis in ["x", "y"])
			if ((v = after('translate-$axis-')) != null) {
				var s = spacing(v, neg, true);
				return s == null ? null : [['--tw-translate-$axis', s], ["translate", "var(--tw-translate-x) var(--tw-translate-y)"]];
			}
		if ((v = after("rotate-")) != null) return one("rotate", (neg ? "calc(" + v + "deg * -1)" : v + "deg"));
		if ((v = after("scale-")) != null)
			return [["--tw-scale-x", v + "%"], ["--tw-scale-y", v + "%"], ["--tw-scale-z", v + "%"], ["scale", "var(--tw-scale-x) var(--tw-scale-y)"]];
		// motion
		if ((v = after("transition")) != null) {
			var props = v == "" ? TRANSITIONS[""] : v.startsWith("-[") ? v.substring(2, v.length - 1).replace("_", " ") : TRANSITIONS[v.substr(1)];
			if (props == null) return null;
			return [["transition-property", props], ["transition-timing-function", "var(--tw-ease, var(--default-transition-timing-function))"],
				["transition-duration", "var(--tw-duration, var(--default-transition-duration))"]];
		}
		if ((v = after("duration-")) != null) return num(v) == null ? null : [["--tw-duration", v + "ms"], ["transition-duration", v + "ms"]];
		if ((v = after("delay-")) != null) return num(v) == null ? null : one("transition-delay", v + "ms");
		if ((v = after("ease-")) != null) {
			var s = v == "linear" ? "linear" : THEME.exists('--ease-$v') ? 'var(--ease-$v)' : null;
			return s == null ? null : [["--tw-ease", s], ["transition-timing-function", s]];
		}
		return null;
	}

	// (an arbitrary shadow's colour as Tailwind writes it: 0 4px 12px var(--tw-shadow-color, rgba(0,0,0,0.1)))
	static function shadowColor(s:String):String {
		var out = [];
		for (part in splitTop(s, ",")) {
			part = part.trim();
			var i = part.indexOf("rgb");
			if (i < 0) i = part.indexOf("#");
			if (i < 0) i = part.indexOf("var(");
			out.push(i < 0 ? part : part.substr(0, i) + "var(--tw-shadow-color, " + part.substr(i) + ")");
		}
		return out.join(", ");
	}

	// (s split at sep outside parentheses)
	static function splitTop(s:String, sep:String):Array<String> {
		var out = [], depth = 0, start = 0;
		for (i in 0...s.length) {
			var ch = s.charAt(i);
			if (ch == "(") depth++ else if (ch == ")") depth-- else if (ch == sep && depth == 0) {
				out.push(s.substring(start, i));
				start = i + 1;
			}
		}
		out.push(s.substr(start));
		return out;
	}

	// (--spacing(8) in an arbitrary property, as Tailwind's function)
	static function theme(v:String):String {
		var i = v.indexOf("--spacing(");
		if (i < 0) return v;
		var j = v.indexOf(")", i);
		return theme(v.substr(0, i) + "calc(var(--spacing) * " + v.substring(i + 10, j) + ")" + v.substr(j + 1));
	}

	// a value with the theme's variables written out and what that leaves
	// to compute computed: calc(var(--spacing) * 4) is 1rem
	public static function resolve(v:String):String {
		if (v.indexOf("var(--") < 0 && v.indexOf("calc(") < 0) return v;
		var re = ~/var\((--[a-z0-9-]+)\)/g;
		var guard = 0;
		while (guard++ < 4) {
			var next = re.map(v, r -> {
				var name = r.matched(1);
				THEME.exists(name) ? THEME[name] : r.matched(0);
			});
			if (next == v) break;
			v = next;
		}
		// calc(0.25rem * 4) and calc(1 / 2 * 100%): numbers
		var mul = ~/calc\(([0-9.]+)(rem|px|%) \* (-?[0-9.]+)\)/g;
		v = mul.map(v, r -> fmt(Std.parseFloat(r.matched(1)) * Std.parseFloat(r.matched(3))) + r.matched(2));
		var frac = ~/calc\(([0-9.]+) \/ ([0-9.]+) \* 100%\)/g;
		v = frac.map(v, r -> fmt(Std.parseFloat(r.matched(1)) / Std.parseFloat(r.matched(2)) * 100) + "%");
		var ratio = ~/calc\(([0-9.]+) \/ ([0-9.]+)\)/g;
		v = ratio.map(v, r -> fmt(Std.parseFloat(r.matched(1)) / Std.parseFloat(r.matched(2))));
		var neg = ~/calc\((-?[0-9.]+)(rem|px|%) \* -1\)/g;
		v = neg.map(v, r -> fmt(-Std.parseFloat(r.matched(1))) + r.matched(2));
		return v;
	}

	// (a value without the spaces CSS does not need; the box-shadow of
	// Tailwind's layers as --tw-box, which every element computes from its own)
	static function minify(v:String):String {
		if (v == BOX_SHADOW) return "var(--tw-box)";
		if (v.indexOf('"') >= 0 || v.indexOf("'") >= 0) return v;
		return v.replace(", ", ",").replace(" / ", "/").replace("( ", "(").replace(" )", ")");
	}

	// (a number shortly: 4 digits after the point at most, no trailing zeros, .5 for 0.5)
	static function fmt(f:Float):String {
		var s = Std.string(Math.round(f * 10000) / 10000);
		if (s.startsWith("0.")) s = s.substr(1) else if (s.startsWith("-0.")) s = "-" + s.substr(2);
		return s;
	}

	#if (macro || sys || eval)
	// the stylesheet of a sheet file (shadcn.json's format; its includes
	// beside it): Tailwind's preflight, the tokens light and dark, then
	// each slot's rules
	public static function sheet(path:String, ?error:(message:String) -> Void):String {
		error = error ?? (m -> throw m);
		var s = Sheet.read(path);
		var out = new StringBuf();
		out.add("/* @hxmc/theme: shadcn/ui (MIT) as CSS, from " + haxe.io.Path.withoutDirectory(path)
			+ " (Css.hx); Tailwind's preflight (MIT, tailwindcss.com) */\n");
		out.add(PREFLIGHT);
		function tokens(m:haxe.DynamicAccess<String>):String
			return [for (k in sorted(m)) '--$k:${m[k]}'].join(";");
		// (the variables the sheet's classes name: --cell-size, --sidebar-width)
		var vars = [for (k in sorted(s.vars)) k + ":" + s.vars[k] + ";"].join("");
		out.add(':root{--radius:${s.radius};--font-sans:${THEME["--font-sans"]};$vars${tokens(s.light)}}\n');
		out.add('.dark{${tokens(s.dark)}}\n');
		out.add('@media (prefers-color-scheme:dark){:root:not(.light){${tokens(s.dark)}}}\n');
		// (shadcn's globals.css: borders and outlines in its colours, the body's)
		out.add("*,::after,::before,::backdrop{border-color:var(--border);outline-color:color-mix(in oklab,var(--ring) 50%,transparent)}body{background-color:var(--background);color:var(--foreground)}\n");
		// (which slots carry a group's or a peer's marker)
		var marked = new Map<String, Array<String>>();
		for (slot in s.slots) {
			var all = [for (l in slot.lists) l.classes].join(" ");
			for (c in ~/\s+/g.split(all))
				if (c == "group" || c == "peer" || c.startsWith("group/") || c.startsWith("peer/")) {
					if (!marked.exists(c)) marked[c] = [];
					marked[c].push(slot.name);
				}
		}
		function slotsSel(names:Array<String>):String
			return names.length == 1 ? '[data-slot=${names[0]}]' : ":is(" + [for (n in names) '[data-slot=$n]'].join(",") + ")";
		function groups(m:String):String
			return marked.exists(m) ? ":where(" + slotsSel(marked[m]) + ")" : ":where(." + escape(m) + ")";
		// ([class*='size-'] on an icon: the icon has a size of its own; here, its own slot)
		function attr(a:String):String
			return "[data-slot]";
		var used = new Map<String, Bool>(), dark = [];
		for (slot in s.slots) {
			// (rules of a selector, in Tailwind's order: their variants', then base, variant, size, class)
			var blocks:Array<{key:String, at:Array<String>, sel:String, order:Array<Int>, layer:Int, decls:Array<Array<String>>}> = [];
			var selected = false;
			for (l in slot.lists) {
				// (base 0, a variant's 1, a size's 2, a class after them 3, as cn's className after cva's)
				if (l.variant != null || l.size != null) selected = true;
				var layer = l.variant != null ? 1 : l.size != null ? 2 : selected ? 3 : 0;
				for (c in ~/\s+/g.split(l.classes.trim())) {
					if (c == "") continue;
					var cls = (l.prefix == null ? "" : l.prefix + ":") + c;
					var rs = rules(cls, groups, attr);
					if (rs == null) {
						error('Css: unknown class $cls (slot ${slot.name})');
						continue;
					}
					var order = variantOrder(cls);
					for (r in rs) {
						if (r.decls.length == 0) continue;
						var self = '[data-slot=${slot.name}]';
						if (l.variant != null) self += ':where([data-variant=${l.variant}])';
						if (l.size != null) self += ':where([data-size=${l.size}])';
						var sel = r.sel.replace("&", self);
						var key = r.at.join("|") + "{" + sel + "|" + layer;
						var b = null;
						for (x in blocks)
							if (x.key == key) b = x;
						if (b == null) blocks.push(b = {key: key, at: r.at, sel: sel, order: order, layer: layer, decls: []});
						for (d in r.decls) {
							// (the later class wins, as tailwind-merge keeps it)
							for (x in b.decls.copy())
								if (x[0] == d[0]) b.decls.remove(x);
							b.decls.push(d);
						}
						var anim = ~/animation: ?var\(--animate-([a-z-]+)\)|animation: ?(caret-blink)/;
						for (d in r.decls)
							if (d[0] == "animation" && anim.match(d[0] + ": " + d[1])) used[anim.matched(1) ?? anim.matched(2)] = true;
					}
				}
			}
			var seq = [for (i in 0...blocks.length) blocks[i].key => i];
			blocks.sort((a, b) -> {
				var c = compareOrder(a.order, b.order);
				if (c == 0) c = a.layer - b.layer;
				c != 0 ? c : seq[a.key] - seq[b.key];
			});
			for (b in blocks) {
				b.decls.sort((x, y) -> propertyOrder(x[0]) - propertyOrder(y[0]));
				var body = b.sel + "{" + [for (d in b.decls) d[0] + ":" + minify(resolve(d[1]))].join(";") + "}";
				for (i in 0...b.at.length)
					body = b.at[b.at.length - 1 - i] + "{" + body + "}";
				out.add(body + "\n");
				// (dark rules again under the system's dark, unless .light)
				if (b.sel.indexOf(":is(.dark *)") >= 0) {
					var d = b.sel.replace(":is(.dark *)", ":is(:root:not(.light) *)");
					var inner = d + "{" + [for (x in b.decls) x[0] + ":" + minify(resolve(x[1]))].join(";") + "}";
					for (i in 0...b.at.length)
						inner = b.at[b.at.length - 1 - i] + "{" + inner + "}";
					dark.push(inner);
				}
			}
		}
		// (the DOM's widgets: their popups' and modals' hosts in the top layer, laid out by their content; icons that point the way the line reads)
		out.add("[data-popup]{position:fixed;inset:auto;margin:0;padding:0;border:0;background:none;color:inherit;overflow:visible}"
			+ "dialog[data-modal]{position:fixed;inset:0;width:100%;height:100%;max-width:none;max-height:none;margin:0;padding:0;border:0;background:none;color:inherit;overflow:visible}dialog[data-modal]::backdrop{background:none}"
			+ "[data-mirrored]:dir(rtl){transform:scaleX(-1)}\n");
		if (dark.length > 0) out.add("@media (prefers-color-scheme:dark){\n" + dark.join("\n") + "\n}\n");
		for (k in sorted(used))
			out.add(KEYFRAMES[k] + "\n");
		return out.toString();
	}

	// writes a sheet's stylesheet: Css <sheet.json> <out.css>, as a build
	// step (haxe -lib hxmc.theme --run hxmc.theme.Css shadcn.json app.css;
	// a bare name is a sheet of this package)
	static function main() {
		var args = Sys.args();
		var path = sys.FileSystem.exists(args[0]) ? args[0] : haxe.io.Path.join([haxe.io.Path.directory(sys.FileSystem.fullPath(Sys.programPath() ?? "")), args[0]]);
		sys.io.File.saveContent(args[1], sheet(path));
	}

	static function sorted(m:Dynamic):Array<String> {
		var keys = Std.isOfType(m, haxe.ds.StringMap) ? [for (k in (m : Map<String, Bool>).keys()) k] : Reflect.fields(m);
		keys.sort(Reflect.compare);
		return keys;
	}
	#end

	// (a class's variants' order, the latest first, as Tailwind's bitmasks compare)
	static function variantOrder(c:String):Array<Int> {
		var parts = Tailwind.splitVariants(c);
		parts.pop();
		var order = [for (v in parts) Tailwind.variantRank(v)];
		order.sort((a, b) -> b - a);
		return order;
	}

	static function compareOrder(a:Array<Int>, b:Array<Int>):Int {
		for (i in 0...(a.length > b.length ? a.length : b.length)) {
			if (i >= a.length) return -1;
			if (i >= b.length) return 1;
			if (a[i] != b[i]) return a[i] - b[i];
		}
		return 0;
	}

	// (shorthands before their longhands, as Tailwind's property order has them)
	static final ORDER = "pointer-events visibility position inset inset-inline inset-block inset-inline-start inset-inline-end top right bottom left z-index order grid-column grid-column-start grid-column-end grid-row grid-row-start grid-row-end margin margin-inline margin-block margin-inline-start margin-inline-end margin-top margin-right margin-bottom margin-left display field-sizing aspect-ratio height max-height min-height width max-width min-width flex flex-shrink flex-grow flex-basis transform-origin translate scale rotate transform animation cursor touch-action grid-auto-rows grid-template-columns grid-template-rows flex-direction flex-wrap place-content place-items align-content align-items justify-content justify-items gap column-gap row-gap align-self justify-self overflow overflow-x overflow-y border-radius border-top-left-radius border-top-right-radius border-bottom-right-radius border-bottom-left-radius border-width border-inline-width border-block-width border-top-width border-right-width border-bottom-width border-left-width border-style border-inline-style border-block-style border-top-style border-right-style border-bottom-style border-left-style border-color background-color fill stroke padding padding-inline padding-block padding-inline-start padding-inline-end padding-top padding-right padding-bottom padding-left text-align vertical-align font-family font-size line-height font-weight letter-spacing text-wrap overflow-wrap white-space color text-decoration-line text-underline-offset opacity box-shadow outline-style outline-width outline-offset outline-color transition transition-property transition-timing-function transition-duration";

	static var orderIndex:Null<Map<String, Int>> = null;

	static function propertyOrder(p:String):Int {
		if (orderIndex == null) {
			orderIndex = new Map();
			var list = ORDER.split(" ");
			for (i in 0...list.length)
				orderIndex[list[i]] = i;
		}
		// (custom properties with the property they feed, before it)
		var i = orderIndex[p];
		return i == null ? -1 : i;
	}

	// Tailwind v4's preflight (its base layer), minified
	static inline var PREFLIGHT = "*,::after,::before,::backdrop,::file-selector-button{box-sizing:border-box;margin:0;padding:0;border:0 solid}html,:host{line-height:1.5;-webkit-text-size-adjust:100%;tab-size:4;font-family:var(--font-sans);font-feature-settings:normal;font-variation-settings:normal;-webkit-tap-highlight-color:transparent}hr{height:0;color:inherit;border-top-width:1px}abbr:where([title]){text-decoration:underline dotted}h1,h2,h3,h4,h5,h6{font-size:inherit;font-weight:inherit}a{color:inherit;text-decoration:inherit}b,strong{font-weight:bolder}code,kbd,samp,pre{font-family:var(--font-mono);font-size:1em}small{font-size:80%}sub,sup{font-size:75%;line-height:0;position:relative;vertical-align:baseline}sub{bottom:-.25em}sup{top:-.5em}table{text-indent:0;border-color:inherit;border-collapse:collapse}progress{vertical-align:baseline}summary{display:list-item}ol,ul,menu{list-style:none}img,svg,video,canvas,audio,iframe,embed,object{display:block;vertical-align:middle}img,video{max-width:100%;height:auto}button,input,select,optgroup,textarea,::file-selector-button{font:inherit;font-feature-settings:inherit;font-variation-settings:inherit;letter-spacing:inherit;color:inherit;border-radius:0;background-color:transparent;opacity:1}::file-selector-button{margin-inline-end:4px}::placeholder{opacity:1;color:color-mix(in oklab,currentcolor 50%,transparent)}textarea{resize:vertical}::-webkit-search-decoration{-webkit-appearance:none}::-webkit-date-and-time-value{min-height:1lh;text-align:inherit}::-webkit-datetime-edit{display:inline-flex}::-webkit-datetime-edit-fields-wrapper{padding:0}::-webkit-calendar-picker-indicator{line-height:1}button,input:where([type=button],[type=reset],[type=submit]),::file-selector-button{appearance:button}::-webkit-inner-spin-button,::-webkit-outer-spin-button{height:auto}[hidden]:where(:not([hidden=until-found])){display:none!important}"
		// (the custom properties Tailwind registers with @property, as initial values)
		+ "*,::before,::after,::backdrop{--tw-translate-x:0;--tw-translate-y:0;--tw-scale-x:1;--tw-scale-y:1;--tw-scale-z:1;--tw-border-style:solid;--tw-outline-style:solid;--tw-shadow:0 0 #0000;--tw-inset-shadow:0 0 #0000;--tw-inset-ring-shadow:0 0 #0000;--tw-ring-shadow:0 0 #0000;--tw-ring-offset-width:0px;--tw-ring-offset-color:#fff;--tw-ring-offset-shadow:0 0 #0000;--tw-leading:initial;--tw-font-weight:initial;--tw-tracking:initial;--tw-duration:initial;--tw-ease:initial;--tw-ring-color:initial;--tw-ring-inset:initial;--tw-shadow-color:initial;--tw-content:'';--tw-box:var(--tw-inset-shadow),var(--tw-inset-ring-shadow),var(--tw-ring-offset-shadow),var(--tw-ring-shadow),var(--tw-shadow)}\n";
}
