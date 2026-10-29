package helder.typescript.check;

import haxe.io.Bytes;
import haxe.ds.Vector;
import helder.typescript.check.Syntax;
import helder.typescript.check.Types.TsType;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Syntax.Protocol.*;

// A source file in tsgo's binary AST encoding, read in place. Nodes form a
// pre-order table of fixed-size records (kind, pos, end, next sibling,
// parent, data, flags); `data` holds a child presence mask, a string table
// index or an extended data offset. Node objects are created on first use
// and are unique per index, so they can be compared and used as keys.
class SourceFile {
	public final path:String;
	public final bytes:Bytes;
	public var root(get, never):Node;
	final nodes:Int;
	final stringOffsets:Int;
	final strings:Int;
	final extended:Int;
	final cache:Vector<Node>;
	public final count:Int;
	var lines:Array<Int>;
	// (checker symbol identities of identifiers, by node index)
	public final symbols:Map<Int, String> = [];
	// (the checker's types of expressions and declared names, and functions' return types, by node index)
	public final types:Map<Int, TsType> = [];
	public final returns:Map<Int, TsType> = [];
	public final tables:Tables;
	public function new(path:String, bytes:Bytes, tables:Tables) {
		this.path = path;
		this.bytes = bytes;
		this.tables = tables;
		nodes = bytes.getInt32(HEADER_OFFSET_NODES);
		stringOffsets = bytes.getInt32(HEADER_OFFSET_STRING_TABLE_OFFSETS);
		strings = bytes.getInt32(HEADER_OFFSET_STRING_TABLE);
		extended = bytes.getInt32(HEADER_OFFSET_EXTENDED_DATA);
		count = Std.int((bytes.length - nodes) / NODE_LEN);
		cache = new Vector(count);
	}

	inline function get_root():Node return node(1);

	public function node(index:Int):Node {
		var n = cache[index];
		if (n == null) {
			n = new Node(this, index);
			cache[index] = n;
		}
		return n;
	}

	public inline function field(index:Int, offset:Int):Int return bytes.getInt32(nodes + index * NODE_LEN + offset);

	public inline function extendedData(index:Int, offset:Int):Int return bytes.getInt32(extended + (field(index, NODE_OFFSET_DATA) & NODE_EXTENDED_DATA_MASK) + offset);

	public function string(i:Int):String {
		var start = bytes.getInt32(stringOffsets + i * 4), end = bytes.getInt32(stringOffsets + i * 4 + 4);
		return decode(start, end);
	}

	// (strings are WTF-8: UTF-8 that can carry lone surrogates)
	function decode(start:Int, end:Int):String {
		var p = strings + start, e = strings + end;
		var plain = true;
		for (i in p...e) if (bytes.get(i) == 0xED) {
			plain = false;
			break;
		}
		if (plain) return bytes.getString(p, e - p);
		var b = new StringBuf();
		while (p < e) {
			var c = bytes.get(p);
			if (c < 0x80) {
				b.addChar(c);
				p++;
			}
			else if (c < 0xE0) {
				b.addChar(((c & 0x1F) << 6) | (bytes.get(p + 1) & 0x3F));
				p += 2;
			}
			else if (c < 0xF0) {
				b.addChar(((c & 0x0F) << 12) | ((bytes.get(p + 1) & 0x3F) << 6) | (bytes.get(p + 2) & 0x3F));
				p += 3;
			}
			else {
				b.addChar(((c & 0x07) << 18) | ((bytes.get(p + 1) & 0x3F) << 12) | ((bytes.get(p + 2) & 0x3F) << 6) | (bytes.get(p + 3) & 0x3F));
				p += 4;
			}
		}
		return b.toString();
	}
	// Positions are UTF-16 offsets into the file text, which is stored as
	// UTF-8: `units` maps each offset to its byte (null for ASCII-only text).
	var textStart = -1;
	var textEnd:Int;
	var units:Vector<Int>;
	function textBytes() {
		if (textStart >= 0) return;
		var text = extendedData(1, 0);
		textStart = strings + bytes.getInt32(stringOffsets + text * 4);
		textEnd = strings + bytes.getInt32(stringOffsets + text * 4 + 4);
		var count = 0, ascii = true;
		var p = textStart;
		while (p < textEnd) {
			var c = bytes.get(p);
			if (c >= 0x80) ascii = false;
			p += c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
			count += c >= 0xF0 ? 2 : 1;
		}
		if (ascii) return;
		units = new Vector(count + 1);
		var i = 0;
		p = textStart;
		while (p < textEnd) {
			var c = bytes.get(p);
			units[i++] = p - textStart;
			if (c >= 0xF0) units[i++] = p - textStart;
			p += c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
		}
		units[count] = textEnd - textStart;
	}

	inline function byte(pos:Int):Int {
		textBytes();
		return units == null ? pos : units[pos];
	}

	function unit(offset:Int):Int {
		if (units == null) return offset;
		var lo = 0, hi = units.length - 1;
		while (lo < hi) {
			var mid = (lo + hi) >> 1;
			if (units[mid] < offset) lo = mid + 1; else hi = mid;
		}
		return lo;
	}

	// A position's byte offset in the source text (as Haxe's positions are).
	public function offset(pos:Int):Int {
		textBytes();
		return byte(pos);
	}

	// The source text between two positions.
	public function slice(from:Int, to:Int):String {
		textBytes();
		return decode(textStart - strings + byte(from), textStart - strings + byte(to));
	}

	// The position of the first token at or after a position (past whitespace and comments).
	public function skipTrivia(pos:Int):Int {
		textBytes();
		var start = textStart, end = textEnd;
		var p = start + byte(pos);
		while (p < end) {
			var c = bytes.get(p);
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code) p++;
			else if (c == "/".code && p + 1 < end && bytes.get(p + 1) == "/".code) {
				while (p < end && bytes.get(p) != "\n".code) p++;
			}
			else if (c == "/".code && p + 1 < end && bytes.get(p + 1) == "*".code) {
				p += 2;
				while (p + 1 < end && !(bytes.get(p) == "*".code && bytes.get(p + 1) == "/".code)) p++;
				p += 2;
			}
			else break;
		}
		return unit(p - start);
	}

	// The 1-based line of a position.
	public function line(pos:Int):Int {
		textBytes();
		if (lines == null) {
			lines = [0];
			for (i in textStart...textEnd) if (bytes.get(i) == "\n".code) lines.push(i - textStart + 1);
		}
		var at = byte(pos);
		var lo = 0, hi = lines.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (lines[mid] <= at) lo = mid; else hi = mid - 1;
		}
		return lo + 1;
	}

	public function text():String return string(extendedData(1, 0));

	public function fileName():String return string(extendedData(1, 4));

	// (the kind of a node by index, in Kind's numbering)
	public inline function kindAt(index:Int):Kind return tables.kind(field(index, NODE_OFFSET_KIND));
}

typedef NodeList = Array<Node>;

class Node extends Children {
	public final file:SourceFile;
	public final index:Int;
	public var kind(get, never):Kind;
	public var pos(get, never):Int;
	public var end(get, never):Int;
	public var flags(get, never):Int;
	public var parent(get, never):Node;
	public var symbol(get, never):Null<String>;
	// the checker's type of an expression or a declared name (Types)
	public var tsType(get, never):Null<TsType>;
	public function new(file:SourceFile, index:Int) {
		this.file = file;
		this.index = index;
	}

	inline function get_kind():Kind return file.kindAt(index);

	inline function get_pos():Int return file.field(index, NODE_OFFSET_POS);

	inline function get_end():Int return file.field(index, NODE_OFFSET_END);

	inline function get_flags():Int return file.field(index, NODE_OFFSET_FLAGS);

	inline function data():Int return file.field(index, NODE_OFFSET_DATA);

	inline function next():Int return file.field(index, NODE_OFFSET_NEXT);

	inline function get_symbol():Null<String> return file.symbols.get(index);

	inline function get_tsType():Null<TsType> return file.types.get(index);

	// a function's return type
	public inline function returnType():Null<TsType> return file.returns.get(index);

	function get_parent():Node {
		if (index <= 1) return null;
		var p = file.field(index, NODE_OFFSET_PARENT);
		while (p > 1 && file.field(p, NODE_OFFSET_KIND) == KIND_NODE_LIST) p = file.field(p, NODE_OFFSET_PARENT);
		return p < 1 ? null : file.node(p);
	}

	inline function hasChildren():Bool return index + 1 < file.count && file.field(index + 1, NODE_OFFSET_PARENT) == index;

	override function child(property:Int):Node {
		var order = file.tables.order(kind, property);
		if (order < 0 || !hasChildren()) return null;
		var d = data();
		var mask = d & 0xC0000000 == NODE_DATA_TYPE_CHILDREN ? d & 0xff : 0xff;
		if (mask & (1 << order) == 0) return null;
		var skip = 0;
		for (i in 0...order) if (mask & (1 << i) != 0) skip++;
		var c = index + 1;
		for (_ in 0...skip) c = file.field(c, NODE_OFFSET_NEXT);
		return file.node(c);
	}

	override function list(property:Int):NodeList {
		var l = child(property);
		if (l == null) return [];
		return (l.kind : Int) == KIND_NODE_LIST ? l.items() : [l];
	}

	// (the members of a node list pseudo-node)
	function items():NodeList {
		var out = [];
		if (data() == 0) return out;
		var c = index + 1;
		while (c != 0) {
			out.push(file.node(c));
			c = file.field(c, NODE_OFFSET_NEXT);
		}
		return out;
	}

	// The child nodes in source order, with lists flattened.
	public function children():NodeList {
		var out = [];
		if (!hasChildren()) return out;
		var c = index + 1;
		while (c != 0) {
			var n = file.node(c);
			if ((n.kind : Int) == KIND_NODE_LIST) for (e in n.items()) out.push(e); else out.push(n);
			c = file.field(c, NODE_OFFSET_NEXT);
		}
		return out;
	}
	public var text(get, never):String;
	function get_text():String return switch (kind) {
		case KindIdentifier | KindPrivateIdentifier | KindJsxText: file.string(data() & NODE_STRING_INDEX_MASK);
		case KindStringLiteral | KindNumericLiteral | KindBigIntLiteral | KindRegularExpressionLiteral | KindNoSubstitutionTemplateLiteral | KindTemplateHead | KindTemplateMiddle | KindTemplateTail | KindSourceFile:
			file.string(file.extendedData(index, 0));
		case _: "";
	}

	// The uncooked text of a template literal piece.
	public function rawText():String return switch (kind) {
		case KindTemplateHead | KindTemplateMiddle | KindTemplateTail: file.string(file.extendedData(index, 4));
		case KindNoSubstitutionTemplateLiteral:
			var source = file.slice(pos, end);
			var start = source.indexOf("`");
			StringTools.replace(StringTools.replace(source.substring(start + 1, source.length - 1), "\r\n", "\n"), "\r", "\n");
		case _: null;
	}

	// (the operator of a unary expression; tokens of other nodes are children)
	public function unaryOperator():Kind {
		var i = (data() >> 24) & 0x7;
		return kind == KindPostfixUnaryExpression ? (i & 1 == 1 ? KindMinusMinusToken : KindPlusPlusToken) : switch (i) {
			case 1: KindMinusToken;
			case 2: KindTildeToken;
			case 3: KindExclamationToken;
			case 4: KindPlusPlusToken;
			case 5: KindMinusMinusToken;
			case _: KindPlusToken;
		};
	}

	public function isTypeOnly():Bool return kind == KindImportClause ? (data() >> 24) & 3 == 1 : (data() >> 24) & 1 == 1;

	public function isExportEquals():Bool return (data() >> 24) & 1 == 1;

	// (`extends` or `implements` of a heritage clause)
	public function token():Kind return (data() >> 24) & 1 == 1 ? KindImplementsKeyword : KindExtendsKeyword;

	// (`new` for new.target, `import` for import.meta)
	public function keywordToken():Kind return (data() >> 24) & 1 == 1 ? KindNewKeyword : KindImportKeyword;

	public function toString():String return kind.toString() + "@" + pos;
}

class NodeFlags {
	public static inline var Let = 1;
	public static inline var Const = 2;
	public static inline var Using = 4;
	public static inline var BlockScoped = 7;
	public static inline var OptionalChain = 32;
}
