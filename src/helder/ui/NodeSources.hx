package helder.ui;

#if ((hxmc.dev || helder.headless) && !macro)
import helder.view.Source;

// The source map's reverse lookup (dev builds, headless runs: helder.view.Source):
// from a position in a file to the nodes made from it. The innermost span
// holding the position wins: an element's tag (every node it made: a
// For's rows are several) or a component's call (the nodes it mounts at
// its top: those whose parent it did not mount).
class NodeSources {
	// the nodes under roots made from the file's line and column (1-based);
	// file a full path, or the end of one ("examples/todo/Todo.hx")
	public static function at(roots:Array<Node>, file:String, line:Int, col:Int):Array<Node> {
		var file = file.split("\\").join("/");
		var best:Null<Source> = null, call = false;
		function better(s:Null<Source>):Bool
			return s != null && same(s.file, file) && s.holds(line, col) && (best == null || s.end - s.start < best.end - best.start);
		function find(n:Node) {
			var l:Located = n;
			if (better(l.source)) {
				best = l.source;
				call = false;
			}
			if (l.sourceComponent != null && better(l.sourceComponent.call)) {
				best = l.sourceComponent.call;
				call = true;
			}
			for (c in n.children)
				find(c);
		}
		for (r in roots)
			find(r);
		var out = [];
		if (best == null) return out;
		function collect(n:Node) {
			var l:Located = n;
			if (!call && l.source == best) out.push(n);
			if (call && l.sourceComponent != null && l.sourceComponent.call == best) {
				var p:Null<Located> = n.parent;
				if (p == null || p.sourceComponent == null || p.sourceComponent.call != best) out.push(n);
			}
			for (c in n.children)
				collect(c);
		}
		for (r in roots)
			collect(r);
		return out;
	}

	static function same(path:String, file:String):Bool
		return path == file || StringTools.endsWith(path, "/" + file);
}
#end
