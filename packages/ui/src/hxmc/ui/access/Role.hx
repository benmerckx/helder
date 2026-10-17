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
	var Dialog;
	// a dialog asking to confirm or cancel (ARIA's alertdialog)
	var AlertDialog;
	var Menu;
	var MenuItem;
	// a menu item checked or not (ARIA's menuitemcheckbox), one of a group of which one is (menuitemradio)
	var MenuItemCheckBox;
	var MenuItemRadio;
	var ListBox;
	var ListBoxOption;
	var ComboBox;
	var Tooltip;
	// a table of rows of cells (ARIA's grid), a column's header
	var Table;
	var Row;
	var Cell;
	var ColumnHeader;
	// a tree of items (Semantics.level: an item's depth, from 1)
	var Tree;
	var TreeItem;
	// a divider between panes, moved by its value (focusable: ARIA's window splitter)
	var Separator;
	// a number typed or stepped (its value and bounds as a range's, its text as a text input's)
	var SpinButton;
	// a row of menus' titles (each a MenuItem opening its Menu)
	var MenuBar;
	// a row of controls (buttons, toggles, menus' buttons), one Tab stop, arrows between them
	var Toolbar;
	// a group of links that navigate (a landmark: ARIA's navigation; breadcrumbs, pages)
	var Navigation;

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
			case Dialog: "dialog";
			case AlertDialog: "alertdialog";
			case Menu: "menu";
			case MenuItem: "menuitem";
			case MenuItemCheckBox: "menuitemcheckbox";
			case MenuItemRadio: "menuitemradio";
			case ListBox: "listbox";
			case ListBoxOption: "option";
			case ComboBox: "combobox";
			case Tooltip: "tooltip";
			case Table: "grid";
			case Row: "row";
			case Cell: "gridcell";
			case ColumnHeader: "columnheader";
			case Tree: "tree";
			case TreeItem: "treeitem";
			case Separator: "separator";
			case SpinButton: "spinbutton";
			case MenuBar: "menubar";
			case Toolbar: "toolbar";
			case Navigation: "navigation";
		}

	// a role whose name comes from its contents' text (ARIA's "name from
	// content"): that text is not a node of its own
	public function namedByContent():Bool
		return switch (cast this : Role) {
			case Button | CheckBox | Switch | RadioButton | Tab | Link | Heading | ListItem | MenuItem | MenuItemCheckBox | MenuItemRadio | ListBoxOption | Tooltip | Row | Cell | ColumnHeader | TreeItem: true;
			case _: false;
		}
}
