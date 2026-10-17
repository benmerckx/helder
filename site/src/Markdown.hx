using StringTools;

typedef Heading = {level:Int, text:String, id:String};

// A small Markdown renderer for the docs, at build time: what the
// repository's Markdown uses (GitHub's flavour): ATX headings with GitHub's
// anchors, paragraphs, lists (nested by indentation, ordered or not),
// fenced code (highlighted: Highlight), tables, block quotes, rules;
// inline code, emphasis, links and autolinks. HTML in the source is
// escaped. Links go through link (a relative .md becomes its page).
class Markdown {
	public final headings:Array<Heading> = [];

	final link:String->String;
	final ids = new Map<String, Int>();
	var lines:Array<String>;
	var i = 0;

	public function new(link:String->String) {
		this.link = link;
	}

	// the page's title: its first heading, else the default
	public static function title(source:String, fallback:String):String {
		for (l in source.split("\n"))
			if (l.startsWith("# ")) return plain(l.substr(2));
		return fallback;
	}

	// inline Markdown as text (a title)
	public static function plain(s:String):String {
		var r = ~/[`*]/g.replace(s, "");
		return ~/\[([^\]]*)\]\([^)]*\)/g.replace(r, "$1").trim();
	}

	public function render(source:String):String {
		lines = source.replace("\r\n", "\n").replace("\t", "    ").split("\n");
		i = 0;
		var b = new StringBuf();
		blocks(b, 0);
		return b.toString();
	}

	static function indentOf(l:String):Int {
		var n = 0;
		while (n < l.length && l.charCodeAt(n) == " ".code)
			n++;
		return n;
	}

	static function blank(l:String):Bool
		return l.trim() == "";

	static final ITEM = ~/^( *)([-*+]|\d+[.)]) +(.*)$/;
	static final FENCE = ~/^( *)(```+|~~~+) *([^ `]*)/;
	static final HEADING = ~/^(#{1,6}) +(.*?)#* *$/;
	static final RULE = ~/^ *([-*_])( *\1){2,} *$/;
	static final TABLE_SEP = ~/^ *\|? *:?-+:? *(\| *:?-+:? *)*\|? *$/;

	// the blocks of lines indented by at least `indent` (a list item's)
	function blocks(b:StringBuf, indent:Int) {
		while (i < lines.length) {
			var l = lines[i];
			if (blank(l)) {
				i++;
				continue;
			}
			if (indentOf(l) < indent) return;
			var s = l.substr(indent);
			if (FENCE.match(s)) {
				fence(b, indent);
			} else if (HEADING.match(s)) {
				heading(b, HEADING.matched(1).length, HEADING.matched(2));
				i++;
			} else if (RULE.match(s)) {
				b.add("<hr>\n");
				i++;
			} else if (s.startsWith(">")) {
				quote(b, indent);
			} else if (ITEM.match(s)) {
				list(b, indent);
			} else if (s.trim().startsWith("|") && i + 1 < lines.length && TABLE_SEP.match(lines[i + 1].substr(indent))) {
				table(b, indent);
			} else {
				paragraph(b, indent);
			}
		}
	}

	function heading(b:StringBuf, level:Int, text:String) {
		var id = slug(text);
		var n = ids.get(id);
		ids.set(id, n == null ? 1 : n + 1);
		if (n != null) id += "-" + n;
		headings.push({level: level, text: plain(text), id: id});
		b.add('<h$level id="$id">${inlines(text)}<a class="anchor" href="#$id" aria-label="Link to this section">#</a></h$level>\n');
	}

	// GitHub's anchors: lower case, punctuation dropped, spaces to dashes
	public static function slug(text:String):String {
		var s = plain(text).toLowerCase();
		var b = new StringBuf();
		for (c in 0...s.length) {
			var ch = s.charAt(c), code = s.charCodeAt(c);
			if ((code >= "a".code && code <= "z".code) || (code >= "0".code && code <= "9".code) || ch == "-" || ch == "_") b.add(ch);
			else if (ch == " ") b.add("-");
			else if (code > 127) b.add(ch);
		}
		return b.toString();
	}

	function fence(b:StringBuf, indent:Int) {
		var open = lines[i].substr(indent);
		FENCE.match(open);
		var marker = FENCE.matched(2), lang = FENCE.matched(3);
		var inner = indent + FENCE.matched(1).length;
		i++;
		var code = [];
		while (i < lines.length && !lines[i].trim().startsWith(marker)) {
			var l = lines[i];
			code.push(indentOf(l) >= inner ? l.substr(inner) : l.ltrim());
			i++;
		}
		i++;
		b.add(Highlight.block(code.join("\n"), lang));
		b.add("\n");
	}

	function quote(b:StringBuf, indent:Int) {
		var inner = [];
		while (i < lines.length && !blank(lines[i]) && lines[i].substr(indent).startsWith(">")) {
			var s = lines[i].substr(indent + 1);
			inner.push(s.startsWith(" ") ? s.substr(1) : s);
			i++;
		}
		var md = new Markdown(link);
		b.add("<blockquote>\n" + md.render(inner.join("\n")) + "</blockquote>\n");
	}

	function list(b:StringBuf, indent:Int) {
		ITEM.match(lines[i].substr(indent));
		var ordered = ~/\d/.match(ITEM.matched(2).charAt(0));
		var base = indent + ITEM.matched(1).length;
		b.add(ordered ? "<ol>\n" : "<ul>\n");
		while (i < lines.length) {
			var l = lines[i];
			if (blank(l)) {
				// a blank line ends the list unless an item or its continuation follows
				var j = i;
				while (j < lines.length && blank(lines[j]))
					j++;
				if (j >= lines.length || indentOf(lines[j]) < base || (indentOf(lines[j]) == base && !ITEM.match(lines[j].substr(base)))) {
					i = j;
					break;
				}
				i = j;
				continue;
			}
			if (indentOf(l) != base || !ITEM.match(l.substr(base))) break;
			var marker = ITEM.matched(2);
			var content = base + ITEM.matched(1).length + marker.length + 1;
			while (content < l.length && l.charCodeAt(content) == " ".code)
				content++;
			// the item's first line, then its continuation lines (a nested list,
			// fence or table starts its blocks)
			var text = [l.substr(content)];
			i++;
			while (i < lines.length && !blank(lines[i])) {
				var li = lines[i], ind = indentOf(li), t = li.trim();
				if (ind <= base && ITEM.match(li.substr(ind))) break;
				if (ind > base && (ITEM.match(t) || FENCE.match(t) || t.startsWith("|") || t.startsWith(">"))) break;
				text.push(t);
				i++;
			}
			b.add("<li>" + inlines(text.join("\n")));
			// nested blocks: lines indented past the marker
			if (i < lines.length && !blank(lines[i]) && indentOf(lines[i]) > base) {
				b.add("\n");
				blocks(b, Std.int(Math.min(indentOf(lines[i]), content)));
			} else if (i < lines.length && blank(lines[i])) {
				var j = i;
				while (j < lines.length && blank(lines[j]))
					j++;
				if (j < lines.length && indentOf(lines[j]) > base && !ITEM.match(lines[j].substr(base))) {
					i = j;
					b.add("\n");
					blocks(b, Std.int(Math.min(indentOf(lines[j]), content)));
				}
			}
			b.add("</li>\n");
		}
		b.add(ordered ? "</ol>\n" : "</ul>\n");
	}

	static function cells(row:String):Array<String> {
		var s = row.trim();
		if (s.startsWith("|")) s = s.substr(1);
		if (s.endsWith("|") && !s.endsWith("\\|")) s = s.substr(0, s.length - 1);
		// split on | outside code spans, \| kept
		var out = [], cur = new StringBuf(), code = false, k = 0;
		while (k < s.length) {
			var c = s.charAt(k);
			if (c == "\\" && s.charAt(k + 1) == "|") {
				cur.add("|");
				k += 2;
				continue;
			}
			if (c == "`") code = !code;
			if (c == "|" && !code) {
				out.push(cur.toString().trim());
				cur = new StringBuf();
			} else cur.add(c);
			k++;
		}
		out.push(cur.toString().trim());
		return out;
	}

	function table(b:StringBuf, indent:Int) {
		var head = cells(lines[i]);
		var aligns = [
			for (c in cells(lines[i + 1])) c.startsWith(":") && c.endsWith(":") ? "center" : c.endsWith(":") ? "right" : ""
		];
		i += 2;
		var empty = Lambda.foreach(head, h -> h == "");
		b.add('<div class="table"><table>\n');
		if (!empty) {
			b.add("<thead><tr>");
			for (k in 0...head.length)
				b.add('<th${aligns[k] != null && aligns[k] != "" ? ' style="text-align:${aligns[k]}"' : ""}>${inlines(head[k])}</th>');
			b.add("</tr></thead>\n");
		}
		b.add("<tbody>\n");
		while (i < lines.length && lines[i].trim().startsWith("|")) {
			var row = cells(lines[i]);
			b.add("<tr>");
			for (k in 0...head.length)
				b.add('<td${aligns[k] != null && aligns[k] != "" ? ' style="text-align:${aligns[k]}"' : ""}>${inlines(row[k] == null ? "" : row[k])}</td>');
			b.add("</tr>\n");
			i++;
		}
		b.add("</tbody></table></div>\n");
	}

	function paragraph(b:StringBuf, indent:Int) {
		var text = [];
		while (i < lines.length && !blank(lines[i]) && indentOf(lines[i]) >= indent) {
			var s = lines[i].substr(indent);
			if (text.length > 0 && (FENCE.match(s) || HEADING.match(s) || s.startsWith(">") || ITEM.match(s) || RULE.match(s))) break;
			text.push(s.trim());
			i++;
		}
		b.add("<p>" + inlines(text.join("\n")) + "</p>\n");
	}

	// inline Markdown to HTML: code spans first (their content kept as is),
	// then links, emphasis
	public function inlines(s:String):String {
		var b = new StringBuf();
		var k = 0;
		while (k < s.length) {
			var c = s.charAt(k);
			if (c == "`") {
				var n = 1;
				while (s.charAt(k + n) == "`")
					n++;
				var fence = s.substr(k, n);
				var end = s.indexOf(fence, k + n);
				if (end > 0) {
					var code = s.substring(k + n, end);
					if (code.startsWith(" ") && code.endsWith(" ") && code.trim() != "") code = code.substr(1, code.length - 2);
					b.add("<code>" + Esc.html(code.replace("\n", " ")) + "</code>");
					k = end + n;
					continue;
				}
				b.add(fence);
				k += n;
				continue;
			}
			if (c == "\\" && k + 1 < s.length && "\\`*_{}[]()#+-.!|<>".indexOf(s.charAt(k + 1)) >= 0) {
				b.add(Esc.html(s.charAt(k + 1)));
				k += 2;
				continue;
			}
			if (c == "[" || (c == "!" && s.charAt(k + 1) == "[")) {
				var image = c == "!";
				var open = image ? k + 1 : k;
				var close = matching(s, open, "[", "]");
				if (close > 0 && s.charAt(close + 1) == "(") {
					var end = matching(s, close + 1, "(", ")");
					if (end > 0) {
						var label = s.substring(open + 1, close);
						var href = s.substring(close + 2, end).trim();
						var sp = href.indexOf(" ");
						if (sp > 0) href = href.substr(0, sp);
						var url = link(href);
						if (image) b.add('<img src="${Esc.html(url)}" alt="${Esc.html(plain(label))}">');
						else b.add('<a href="${Esc.html(url)}">${inlines(label)}</a>');
						k = end + 1;
						continue;
					}
				}
			}
			if (c == "<") {
				var end = s.indexOf(">", k);
				if (end > 0) {
					var inner = s.substring(k + 1, end);
					if (~/^(https?:\/\/|mailto:)[^ <>]+$/.match(inner)) {
						b.add('<a href="${Esc.html(inner)}">${Esc.html(inner)}</a>');
						k = end + 1;
						continue;
					}
				}
			}
			if ((c == "*" || c == "_") && s.charAt(k + 1) == c) {
				var end = s.indexOf(c + c, k + 2);
				if (end > k + 2 && s.charAt(k + 2) != " ") {
					b.add("<strong>" + inlines(s.substring(k + 2, end)) + "</strong>");
					k = end + 2;
					continue;
				}
			}
			if (c == "*" || (c == "_" && (k == 0 || !isWord(s.charCodeAt(k - 1))))) {
				var end = k + 1;
				while (true) {
					end = s.indexOf(c, end);
					if (end < 0) break;
					if (s.charAt(end + 1) == c) {
						end += 2;
						continue;
					}
					if (c == "_" && end + 1 < s.length && isWord(s.charCodeAt(end + 1))) {
						end++;
						continue;
					}
					break;
				}
				if (end > k + 1 && s.charAt(k + 1) != " " && s.charAt(end - 1) != " ") {
					b.add("<em>" + inlines(s.substring(k + 1, end)) + "</em>");
					k = end + 1;
					continue;
				}
			}
			if (c == "\n") {
				b.add("\n");
				k++;
				continue;
			}
			b.add(Esc.html(c));
			k++;
		}
		return b.toString();
	}

	static function isWord(c:Int):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code);

	// the index of the bracket closing the one at `at`, nesting counted; -1 if none
	static function matching(s:String, at:Int, open:String, close:String):Int {
		var depth = 0, k = at;
		while (k < s.length) {
			var c = s.charAt(k);
			if (c == "`") {
				var e = s.indexOf("`", k + 1);
				if (e > 0) {
					k = e + 1;
					continue;
				}
			}
			if (c == open) depth++;
			else if (c == close) {
				depth--;
				if (depth == 0) return k;
			}
			k++;
		}
		return -1;
	}
}
