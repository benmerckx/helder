import helder.ui.*;

// A headless Ui for the TypeScript tests (tests/typescript/helder/ui.tsx,
// declared to them by UiTypeScript): its root to render into, pointer,
// keys and text sent to it as a window would, its tree written out (each
// node's tag, a text's text, what it is to assistive technology).
class UiProbe {
	static var ui:Null<Ui> = null;

	// a Ui of width x height (MonoText's text), its root
	@:typescript public static function root(width:Int, height:Int):Node {
		ui = new Ui(new MonoText(), width, height);
		return ui.root;
	}

	// a click on the first node with tag (laid out first)
	@:typescript public static function click(tag:String) {
		ui.update();
		var n = ui.root.find(tag);
		if (n == null) throw 'UiProbe: no node $tag';
		ui.pointerDown(n.absX + n.width / 2, n.absY + n.height / 2, 1);
		ui.pointerUp(n.absX + n.width / 2, n.absY + n.height / 2, 1);
		ui.update();
	}

	// text typed into the focused node
	@:typescript public static function type(text:String) {
		for (c in new haxe.iterators.StringIteratorUnicode(text)) {
			ui.keyDown(c, 0);
			ui.textInput(String.fromCharCode(c));
		}
		ui.update();
	}

	// a key pressed (Key's codes)
	@:typescript public static function key(code:Int) {
		ui.keyDown(code, 0);
		ui.update();
	}

	// the tree: a node a line, indented by its depth
	@:typescript public static function dump():String {
		ui.update();
		var out = new StringBuf();
		function walk(n:Node, depth:Int) {
			if (n.style.display == None) return;
			out.add(StringTools.lpad("", " ", depth * 2) + n.tag);
			if (Std.isOfType(n, TextNode)) out.add(' "' + (cast n : TextNode).text + '"');
			var s = n.semantics;
			if (s != null && s.checked != null) out.add(s.checked ? " checked" : " unchecked");
			out.add("\n");
			for (c in n.children)
				walk(c, depth + 1);
		}
		walk(ui.root, 0);
		return out.toString();
	}
}
