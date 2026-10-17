// The widgets' reference, read from their sources (the component pages of
// the site): for each public widget of Widgets.hx, its doc comment, its
// props (name, type, whether optional, a default where the code gives one:
// props.x ?? value), the slots and data- attributes a theme targets, the
// roles it declares, and what its @:widget metadata says (props: each
// one's doc; variants, sizes; keys: what each key does, written out as
// [{keys, does}] in their order; part: the widget whose part it is,
// documented and shown with it; popup: its parts show only when the user
// opens it), and its example
// (examples/widgets/<Name>Example.hx) when there is one; host: "drawn"
// (hxmc.ui's own) unless the metadata says otherwise.
//   WidgetDocs <Widgets.hx> <examples dir> [out.json]
class WidgetDocs {
	// (the props most widgets take, documented once)
	static final COMMON:haxe.DynamicAccess<String> = {
		tag: "its node's tag (Node.find, tests)",
		style: "a function of its states (States: hovered, pressed, focused...) giving its own style, over the theme's",
		children: "its content"
	};

	public static function read(source:String, examples:Null<String>):Array<Dynamic> {
		var lines = source.split("\n"), out:Array<Dynamic> = [], comment:Array<String> = [], meta:Null<String> = null;
		helpers = helperSlots(lines);
		var i = 0;
		while (i < lines.length) {
			var l = lines[i];
			if (StringTools.startsWith(l, "\t// ")) {
				comment.push(StringTools.trim(l.substr(4)));
				i++;
				continue;
			}
			if (StringTools.startsWith(l, "\t@:widget(")) {
				// (to its closing parenthesis, over lines)
				var text = l.substr(10);
				while (!StringTools.endsWith(StringTools.trim(text), ")") && i + 1 < lines.length)
					text += "\n" + lines[++i];
				meta = StringTools.trim(text);
				meta = meta.substr(0, meta.length - 1);
				i++;
				continue;
			}
			var fn = ~/^\tpublic static function ([A-Z][A-Za-z]*)(<[^>]*>)?\(/;
			if (fn.match(l)) {
				var name = fn.matched(1);
				// (the signature to its return type, the body to the next member)
				var sig = l, j = i;
				while (sig.indexOf("):") < 0 && j + 1 < lines.length)
					sig += " " + StringTools.trim(lines[++j]);
				var body = [];
				j++;
				while (j < lines.length && !~/^\t(\/\/|public|static|@:)/.match(lines[j]) && lines[j] != "}")
					body.push(lines[j++]);
				out.push(widget(name, comment.join(" "), sig, body.join("\n"), meta, examples));
				comment = [];
				meta = null;
				i = j;
				continue;
			}
			if (StringTools.trim(l) == "" || !StringTools.startsWith(l, "\t//")) {
				comment = [];
				meta = null;
			}
			i++;
		}
		return out;
	}

	// (the private helpers' slots made of their kind argument: menuItems's "{kind}-item"...)
	static var helpers = new Map<String, Array<String>>();

	static function helperSlots(lines:Array<String>):Map<String, Array<String>> {
		var out = new Map<String, Array<String>>(), fn = ~/^\tstatic function ([a-z][A-Za-z]*)\(kind:String/;
		for (i in 0...lines.length)
			if (fn.match(lines[i])) {
				var body = [], j = i + 1;
				while (j < lines.length && !~/^\t(\/\/|public|static|@:)/.match(lines[j]) && lines[j] != "}")
					body.push(lines[j++]);
				// (a slot named by a string after the kind: on a line that makes a slot)
				var lines = [for (l in body) if (l.indexOf("slot") >= 0 || l.indexOf("content") >= 0) ~/tag \+ "[^"]*"/g.replace(l, "")];
				out.set(fn.matched(1), found(~/"(-[a-z0-9-]+)"/, lines.join("\n")));
			}
		return out;
	}

	static function widget(name:String, doc:String, sig:String, body:String, meta:Null<String>, examples:Null<String>):Dynamic {
		var w:Dynamic = {name: name, doc: doc, props: props(sig, body), slots: found(~/slot=\{?(?:kind \+ )?"([a-z0-9-]+)"/, body, (m, s) -> StringTools.startsWith(s, "-") ? "{kind}" + s : s)
			.concat(found(~/\.slot = "([a-z0-9-]+)"/, body)), states: found(~/(data-[a-z-]+)=/, body), roles: found(~/role="([a-z]+)"/, body)
			.concat(found(~/Role\.([A-Za-z]+)/, body))};
		// (a helper called with a kind: its slots of that kind)
		var calls = ~/([a-z][A-Za-z]*)\("([a-z-]+)"/, pos = 0;
		while (calls.matchSub(body, pos)) {
			var h = helpers.get(calls.matched(1));
			if (h != null)
				for (slot in h) {
					var v = calls.matched(2) + slot;
					if ((w.slots : Array<String>).indexOf(v) < 0) w.slots.push(v);
				}
			var p = calls.matchedPos();
			pos = p.pos + p.len;
		}
		w.host = "drawn";
		if (meta != null) {
			var m:Dynamic = haxe.Json.parse(json(meta));
			for (k in Reflect.fields(m))
				if (k != "props") Reflect.setField(w, k, Reflect.field(m, k));
			// (the keys in the order written: an object's fields have none)
			var at = meta.indexOf("keys:");
			if (at >= 0) {
				var keys:haxe.DynamicAccess<String> = m.keys, close = meta.indexOf("}", meta.indexOf("{", at));
				w.keys = [for (k in found(~/"((?:[^"\\]|\\.)*)"\s*:/, meta.substring(at, close))) {keys: k, does: keys[k]}];
			}
			var docs:haxe.DynamicAccess<String> = m.props;
			if (docs != null) for (p in (w.props : Array<Dynamic>))
				if (docs.exists(p.name)) p.doc = docs[p.name];
		}
		for (p in (w.props : Array<Dynamic>))
			if (p.doc == null && COMMON.exists(p.name)) p.doc = COMMON[p.name];
		if (examples != null) {
			var file = examples + "/" + name + "Example.hx";
			if (sys.FileSystem.exists(file)) w.example = sys.io.File.getContent(file);
		}
		return w;
	}

	// (a Haxe object literal of strings, arrays and objects as JSON: its keys
	// quoted, outside its strings; a trailing comma dropped)
	static function json(s:String):String {
		var out = new StringBuf(), i = 0, key = ~/^([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:/;
		while (i < s.length) {
			var c = s.charAt(i);
			if (c == "\"") {
				var j = i + 1;
				while (j < s.length && s.charAt(j) != "\"")
					j += s.charAt(j) == "\\" ? 2 : 1;
				out.add(s.substring(i, j + 1));
				i = j + 1;
			} else if ((c == "{" || c == ",") && key.match(s.substr(i))) {
				out.add(key.matched(1) + "\"" + key.matched(2) + "\":");
				i += key.matchedPos().len;
			} else if (c == "," && ~/^,\s*[}\]]/.match(s.substr(i))) {
				i++;
			} else {
				out.add(c);
				i++;
			}
		}
		return out.toString();
	}

	// (each match's group 1, once each, in order)
	static function found(r:EReg, text:String, ?f:(EReg, String) -> String):Array<String> {
		var out = [], pos = 0;
		while (r.matchSub(text, pos)) {
			var v = f == null ? r.matched(1) : f(r, r.matched(1));
			if (out.indexOf(v) < 0) out.push(v);
			var p = r.matchedPos();
			pos = p.pos + p.len;
		}
		return out;
	}

	// (the props of the signature's anonymous type, with the defaults the body gives them)
	static function props(sig:String, body:String):Array<Dynamic> {
		var start = sig.indexOf("props:{");
		if (start < 0) return [];
		var depth = 0, from = start + 7, parts = [], cur = new StringBuf();
		for (k in from...sig.length) {
			var c = sig.charAt(k);
			if (c == "{" || c == "<" || c == "(" || c == "[") depth++;
			if (c == "}" || c == ">" && sig.charAt(k - 1) != "-" || c == ")" || c == "]") {
				if (depth == 0) break;
				depth--;
			}
			if (c == "," && depth == 0) {
				parts.push(cur.toString());
				cur = new StringBuf();
			} else
				cur.add(c);
		}
		parts.push(cur.toString());
		var out = [];
		for (p in parts) {
			p = StringTools.trim(p);
			if (p == "") continue;
			var optional = StringTools.startsWith(p, "?");
			if (optional) p = p.substr(1);
			var colon = p.indexOf(":");
			var name = p.substr(0, colon), type = StringTools.trim(p.substr(colon + 1));
			var prop:Dynamic = {name: name, type: type, optional: optional};
			var d = new EReg("props\\." + name + " \\?\\? ([^;),\\]}]+)", "");
			if (d.match(body)) prop.def = StringTools.trim(d.matched(1));
			out.push(prop);
		}
		return out;
	}

	// what the reference lacks: a widget with no doc, a prop with none, a
	// widget (not a part) with no example
	public static function missing(docs:Array<Dynamic>):Array<String> {
		var out = [];
		for (w in docs) {
			if (w.doc == "" && w.part == null) out.push(w.name + ": no doc comment");
			for (p in (w.props : Array<Dynamic>))
				if (p.doc == null) out.push(w.name + "." + p.name + ": no doc");
			if (w.example == null && w.part == null) out.push(w.name + ": no example");
		}
		return out;
	}

	static function main() {
		var args = Sys.args();
		var docs = read(sys.io.File.getContent(args[0]), args.length > 1 ? args[1] : null);
		var text = haxe.Json.stringify(docs, null, "\t");
		if (args.length > 2) sys.io.File.saveContent(args[2], text + "\n") else Sys.println(text);
	}
}
