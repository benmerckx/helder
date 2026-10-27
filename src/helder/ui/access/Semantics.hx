package helder.ui.access;

// What a node declares about itself for assistive technology (Node.semantics;
// in markup, the attributes role, label, description, href, checked, selected,
// expanded, level, disabled, value-now, value-min, value-max, value-text,
// multiselectable, live, current, hidden). Unset
// fields say nothing: a TextNode is a Label of its text, an ImageNode an
// Image, a focusable node a Group.
@:structInit class Semantics {
	public var role(default, set):Null<Role> = null;
	// the name (else from the contents' text, for the roles named by content)
	public var label(default, set):Null<String> = null;
	public var description(default, set):Null<String> = null;
	// where a link goes (markup: href, making the node a Link): a document's link annotation, the browser's
	public var href(default, set):Null<String> = null;
	public var checked(default, set):Null<Bool> = null;
	// a checkbox neither checked nor not (ARIA's checked="mixed"; markup: checked="mixed")
	public var mixed(default, set):Bool = false;
	public var selected(default, set):Null<Bool> = null;
	// a list box (or tree, table) whose options can be selected together
	public var multiselectable(default, set):Bool = false;
	public var expanded(default, set):Null<Bool> = null;
	// a tree item's depth (from 1)
	public var level(default, set):Null<Int> = null;
	public var disabled(default, set):Bool = false;
	// a range's value (Slider, ProgressIndicator) and bounds, and its text
	public var valueNow(default, set):Null<Float> = null;
	public var valueMin(default, set):Null<Float> = null;
	public var valueMax(default, set):Null<Float> = null;
	public var valueText(default, set):Null<String> = null;
	// a password's text: shown and given to assistive technology as dots
	public var secret(default, set):Bool = false;
	// a region whose changes are announced (its text when it changes; a Group
	// when it has no role of its own)
	public var live(default, set):Live = Off;
	// the current one of a set (ARIA's aria-current="page": a breadcrumb's last, a page's link)
	public var current(default, set):Bool = false;
	// left out with its subtree (decoration)
	public var hidden(default, set):Bool = false;

	// (a change: the accessibility trees built again)
	function set_role(v:Null<Role>):Null<Role> {
		if (v != role) helder.ui.Ui.accessEpoch++;
		return role = v;
	}

	function set_label(v:Null<String>):Null<String> {
		if (v != label) helder.ui.Ui.accessEpoch++;
		return label = v;
	}

	function set_description(v:Null<String>):Null<String> {
		if (v != description) helder.ui.Ui.accessEpoch++;
		return description = v;
	}

	function set_href(v:Null<String>):Null<String> {
		if (v != href) helder.ui.Ui.accessEpoch++;
		return href = v;
	}

	function set_checked(v:Null<Bool>):Null<Bool> {
		if (v != checked) helder.ui.Ui.accessEpoch++;
		return checked = v;
	}

	function set_secret(v:Bool):Bool {
		if (v != secret) helder.ui.Ui.accessEpoch++;
		return secret = v;
	}

	function set_current(v:Bool):Bool {
		if (v != current) helder.ui.Ui.accessEpoch++;
		return current = v;
	}

	function set_multiselectable(v:Bool):Bool {
		if (v != multiselectable) helder.ui.Ui.accessEpoch++;
		return multiselectable = v;
	}

	function set_live(v:Live):Live {
		if (v != live) helder.ui.Ui.accessEpoch++;
		return live = v;
	}

	function set_mixed(v:Bool):Bool {
		if (v != mixed) helder.ui.Ui.accessEpoch++;
		return mixed = v;
	}

	function set_selected(v:Null<Bool>):Null<Bool> {
		if (v != selected) helder.ui.Ui.accessEpoch++;
		return selected = v;
	}

	function set_expanded(v:Null<Bool>):Null<Bool> {
		if (v != expanded) helder.ui.Ui.accessEpoch++;
		return expanded = v;
	}

	function set_level(v:Null<Int>):Null<Int> {
		if (v != level) helder.ui.Ui.accessEpoch++;
		return level = v;
	}

	function set_disabled(v:Bool):Bool {
		if (v != disabled) helder.ui.Ui.accessEpoch++;
		return disabled = v;
	}

	function set_valueNow(v:Null<Float>):Null<Float> {
		if (v != valueNow) helder.ui.Ui.accessEpoch++;
		return valueNow = v;
	}

	function set_valueMin(v:Null<Float>):Null<Float> {
		if (v != valueMin) helder.ui.Ui.accessEpoch++;
		return valueMin = v;
	}

	function set_valueMax(v:Null<Float>):Null<Float> {
		if (v != valueMax) helder.ui.Ui.accessEpoch++;
		return valueMax = v;
	}

	function set_valueText(v:Null<String>):Null<String> {
		if (v != valueText) helder.ui.Ui.accessEpoch++;
		return valueText = v;
	}

	function set_hidden(v:Bool):Bool {
		if (v != hidden) helder.ui.Ui.accessEpoch++;
		return hidden = v;
	}
}
