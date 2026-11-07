package helder.view;

import helder.view.Source;

// What the planner's code calls (MarkupMacro's, TSX's lowering's): spans
// made once per place, elements told theirs, components put in the
// ownership tree (a context of the component's owner: what it mounts
// later, a For's new row, a Show's content, finds it too)
class Sources {
	static final spans = new Map<String, Source>();
	static final components = new Map<String, SourceComponent>();
	static final context = new helder.view.graph.Context<SourceComponent>(null, true);

	// the span (the same object for the same place)
	public static function span(file:String, start:Int, end:Int, line:Int, col:Int, endLine:Int, endCol:Int):Source {
		var key = file + ":" + start + ":" + end;
		var s = spans.get(key);
		if (s == null) {
			s = new Source(file, start, end, line, col, endLine, endCol);
			spans.set(key, s);
		}
		return s;
	}

	// an element made by the tag at s
	public static function element(node:Dynamic, s:Source) {
		if (!Std.isOfType(node, Located)) return;
		var l:Located = cast node;
		l.source = s;
		l.sourceComponent = current();
	}

	// a component's factory starting, in the component's own owner (ViewRuntime.component's)
	public static function enter(name:String, call:Source, definition:Null<Source>) {
		if (helder.view.graph.Owner.current == null) return;
		var key = call.toString();
		var c = components.get(key);
		if (c == null) {
			c = new SourceComponent(name, call, definition);
			components.set(key, c);
		}
		helder.view.graph.Owner.setContext(context, c);
	}

	// the innermost component being mounted where the code runs (null: none)
	public static function current():Null<SourceComponent>
		return helder.view.graph.Owner.current == null ? null : helder.view.graph.Owner.use(context);
}
