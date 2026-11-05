package helder.ui;

import helder.view.graph.Graph;
import helder.view.graph.Signal;

// A handle on a node's focus (GPUI's FocusHandle), made before the node is:
// markup's track-focus={handle} ties it to its node. focus() moves the
// focus there (once it is in a Ui); focused and within (it or a
// descendant: :focus-within) are signals, kept by the Ui as its focus moves
// (written at the event's end, as signals are; isFocused and containsFocus: now).
class FocusHandle {
	public var node(default, null):Null<Node> = null;
	public final focused:Signal<Bool> = Graph.signal(false);
	public final within:Signal<Bool> = Graph.signal(false);

	public function new() {}

	// (markup's track-focus: the node it is for, made focusable)
	public function track(n:Node) {
		if (node != null) @:privateAccess node.focusHandle = null;
		node = n;
		n.focusable = true;
		@:privateAccess n.focusHandle = this;
	}

	public function focus(visible = true)
		if (node != null) node.focus(visible);

	public function blur()
		if (node != null && node.ui != null && node.ui.focus == node) node.ui.setFocus(null);

	public function isFocused():Bool
		return node != null && node.ui != null && node.ui.focus == node;

	public function containsFocus():Bool
		return node != null && node.focusWithin();
}
