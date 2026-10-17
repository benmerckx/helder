package hxmc.ui.native;

// The platform controls hxmc.ui.native has (a Control's kind)
enum abstract ControlKind(Int) to Int {
	var Button;
	// a TextNode's text, as the platform draws text
	var Label;
	var TextField;
	var CheckBox;
	var Slider;
	var Progress;
}
