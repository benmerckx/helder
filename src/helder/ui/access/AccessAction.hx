package helder.ui.access;

// What assistive technology asks a node to do (Ui.accessAction)
enum abstract AccessAction(Int) from Int to Int {
	// activate it: a Click event at its centre
	var Click;
	// give it the keyboard focus
	var Focus;
	// a range: one step up or down (the arrow keys it takes)
	var Increment;
	var Decrement;
	// a text input: its text replaced (the value given)
	var SetValue;
	// an expandable node opened or closed (a click when it is the other way)
	var Expand;
	var Collapse;
	// its scrolling ancestors scrolled to show it
	var ScrollIntoView;
	// a text input's selection set (the value given: "start,end", UTF-16 indices)
	var SetSelection;
	// an item chosen (a click when it is not selected)
	var Select;
}
