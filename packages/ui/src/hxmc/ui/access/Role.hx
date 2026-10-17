package hxmc.ui.access;

// What a node is to assistive technology (AccessKit's roles, which follow
// Chromium's and ARIA's; the browser adapter maps each to its ARIA role)
enum abstract Role(Int) to Int {
	// a node that only groups others (shown when it has a name or is focusable)
	var Group;
	var Button;
	var CheckBox;
	var Switch;
	var RadioGroup;
	var RadioButton;
	var Slider;
	var ProgressIndicator;
	var TextInput;
	var MultilineTextInput;
	// text: a TextNode's own (its name is the text)
	var Label;
	var Image;
	var TabList;
	var Tab;
	var TabPanel;
	var ScrollView;
	var List;
	var ListItem;
	var Heading;
	var Link;

	// the ARIA role of each (the browser's mirror)
	public function aria():String
		return switch (cast this : Role) {
			case Group: "group";
			case Button: "button";
			case CheckBox: "checkbox";
			case Switch: "switch";
			case RadioGroup: "radiogroup";
			case RadioButton: "radio";
			case Slider: "slider";
			case ProgressIndicator: "progressbar";
			case TextInput | MultilineTextInput: "textbox";
			case Label: "text";
			case Image: "img";
			case TabList: "tablist";
			case Tab: "tab";
			case TabPanel: "tabpanel";
			case ScrollView: "region";
			case List: "list";
			case ListItem: "listitem";
			case Heading: "heading";
			case Link: "link";
		}

	// a role whose name comes from its contents' text (ARIA's "name from
	// content"): that text is not a node of its own
	public function namedByContent():Bool
		return switch (cast this : Role) {
			case Button | CheckBox | Switch | RadioButton | Tab | Link | Heading | ListItem: true;
			case _: false;
		}
}
