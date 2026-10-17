package hxmc.ui.access;

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
}
