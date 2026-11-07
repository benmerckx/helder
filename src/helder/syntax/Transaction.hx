package helder.syntax;

// One edit of a file: its changes, each a range of the text it was made
// against replaced by new text, in order and not overlapping. Applied to
// that text it gives the edited one; its inverse, applied to the edited
// one, gives the text back (undo: Document.apply(tx.inverse)). Nothing
// outside the changes' ranges moves but by the length they add.
class Transaction {
	public final changes:Array<Change>;
	// the edited text's transaction back to the text this one was made against
	public final inverse:Transaction;

	// changes against a text (sorted; an insertion at a replacement's start merged into it); overlapping ones an error
	public function new(changes:Array<Change>, ?inverseOf:Transaction, ?base:String) {
		var cs = changes.copy();
		cs.sort((a, b) -> a.start != b.start ? a.start - b.start : a.end - b.end);
		var merged:Array<Change> = [];
		for (c in cs) {
			var last = merged.length > 0 ? merged[merged.length - 1] : null;
			if (last != null && last.start == c.start && last.end == last.start) {
				merged[merged.length - 1] = new Change(c.start, c.end, last.text + c.text);
				continue;
			}
			if (last != null && c.start < last.end) throw new SourceError("helder.syntax: overlapping changes (" + last + ", " + c + ")");
			merged.push(c);
		}
		this.changes = merged;
		this.inverse = inverseOf != null ? inverseOf : base == null ? null : new Transaction(invert(merged, base), this);
	}

	// the changes against base, inverted: each the edited text's range of its new text, given the old text back
	static function invert(cs:Array<Change>, base:String):Array<Change> {
		var out = [], delta = 0;
		for (c in cs) {
			var start = c.start + delta;
			out.push(new Change(start, start + c.text.length, base.substring(c.start, c.end)));
			delta += c.text.length - (c.end - c.start);
		}
		return out;
	}

	// the text edited
	public function apply(text:String):String {
		var b = new StringBuf(), at = 0;
		for (c in changes) {
			if (c.end > text.length) throw new SourceError("helder.syntax: a change past the end of the text (" + c + ")");
			b.addSub(text, at, c.start - at);
			b.add(c.text);
			at = c.end;
		}
		b.addSub(text, at, text.length - at);
		return b.toString();
	}

	// where an offset of the text before is in the text after (one inside a replaced range: its start's; after: assoc > 0)
	public function map(offset:Int, assoc = -1):Int {
		var delta = 0;
		for (c in changes) {
			if (offset < c.start || (offset == c.start && assoc < 0 && c.end > c.start)) break;
			if (offset == c.start && c.end == c.start) {
				if (assoc < 0) break;
				delta += c.text.length;
				continue;
			}
			if (offset < c.end) return c.start + delta + (assoc > 0 ? c.text.length : 0);
			delta += c.text.length - (c.end - c.start);
		}
		return offset + delta;
	}

	// this one, then next (made against this one's result): one transaction against this one's base
	public function then(next:Transaction, base:String):Transaction {
		var mid = apply(base);
		var after = next.apply(mid);
		// (the smallest range that differs: before it and after it, the texts the same)
		var a = 0;
		while (a < base.length && a < after.length && StringTools.fastCodeAt(base, a) == StringTools.fastCodeAt(after, a))
			a++;
		var e1 = base.length, e2 = after.length;
		while (e1 > a && e2 > a && StringTools.fastCodeAt(base, e1 - 1) == StringTools.fastCodeAt(after, e2 - 1)) {
			e1--;
			e2--;
		}
		return new Transaction(a == e1 && a == e2 ? [] : [new Change(a, e1, after.substring(a, e2))], null, base);
	}

	public function toString():String
		return "Transaction(" + changes.join(", ") + ")";
}

class Change {
	public final start:Int;
	public final end:Int;
	public final text:String;

	public function new(start:Int, end:Int, text:String) {
		if (end < start) throw new SourceError("helder.syntax: a change ending before it starts");
		this.start = start;
		this.end = end;
		this.text = text;
	}

	public function toString():String
		return '$start-$end:' + haxe.Json.stringify(text);
}

// An edit the library cannot make: no such node, syntax it does not edit structurally
class SourceError extends haxe.Exception {}
