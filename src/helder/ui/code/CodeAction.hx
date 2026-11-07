package helder.ui.code;

import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;

// A code editor's actions (helder.ui.actions: "code::MoveWordLeft" in a
// keymap), bound by default in the context CodeEditor (the text) and
// CodeFind (the find and go to line panels); a user's keymap changes them.
enum CodeAction {
	MoveLeft;
	MoveRight;
	MoveUp;
	MoveDown;
	MoveWordLeft;
	MoveWordRight;
	MoveLineStart;
	MoveLineEnd;
	MovePageUp;
	MovePageDown;
	MoveDocStart;
	MoveDocEnd;
	SelectLeft;
	SelectRight;
	SelectUp;
	SelectDown;
	SelectWordLeft;
	SelectWordRight;
	SelectLineStart;
	SelectLineEnd;
	SelectPageUp;
	SelectPageDown;
	SelectDocStart;
	SelectDocEnd;
	SelectAll;
	SelectLine;
	Backspace;
	Delete;
	DeleteWordLeft;
	DeleteWordRight;
	Newline;
	Indent;
	Outdent;
	ToggleComment;
	DuplicateLineDown;
	DuplicateLineUp;
	MoveLineUp;
	MoveLineDown;
	DeleteLine;
	AddCursorAbove;
	AddCursorBelow;
	AddNextOccurrence;
	Cancel;
	Undo;
	Redo;
	Copy;
	Cut;
	Paste;
	Find;
	Replace;
	FindNext;
	FindPrevious;
	ReplaceOne;
	ReplaceAll;
	GoToLine;
	ClosePanel;
}

class CodeActions {
	static var declared = false;

	// the actions declared and their default bindings added to the global keymap (once)
	public static function declare() {
		if (declared) return;
		declared = true;
		actions("code", CodeAction);
		var k = Keymap.global, ed = "CodeEditor", find = "CodeFind";
		var list:Array<Array<Dynamic>> = [
			["left", MoveLeft], ["right", MoveRight], ["up", MoveUp], ["down", MoveDown], ["home", MoveLineStart], ["end", MoveLineEnd],
			["pageup", MovePageUp], ["pagedown", MovePageDown], ["shift-left", SelectLeft], ["shift-right", SelectRight], ["shift-up", SelectUp],
			["shift-down", SelectDown], ["shift-home", SelectLineStart], ["shift-end", SelectLineEnd], ["shift-pageup", SelectPageUp],
			["shift-pagedown", SelectPageDown], ["secondary-home", MoveDocStart], ["secondary-end", MoveDocEnd], ["secondary-shift-home", SelectDocStart],
			["secondary-shift-end", SelectDocEnd], ["secondary-a", SelectAll], ["secondary-l", SelectLine], ["backspace", Backspace],
			["shift-backspace", Backspace], ["delete", Delete], ["enter", Newline], ["shift-enter", Newline], ["tab", Indent], ["shift-tab", Outdent],
			["secondary-]", Indent], ["secondary-[", Outdent], ["secondary-/", ToggleComment], ["shift-alt-down", DuplicateLineDown],
			["shift-alt-up", DuplicateLineUp], ["secondary-shift-d", DuplicateLineDown], ["alt-up", MoveLineUp], ["alt-down", MoveLineDown],
			["secondary-shift-k", DeleteLine], ["secondary-alt-up", AddCursorAbove], ["secondary-alt-down", AddCursorBelow], ["secondary-d", AddNextOccurrence],
			["escape", Cancel], ["secondary-z", Undo], ["secondary-shift-z", Redo], ["secondary-y", Redo], ["secondary-c", Copy], ["secondary-x", Cut],
			["secondary-v", Paste], ["secondary-f", Find], ["secondary-h", Replace], ["secondary-alt-f", Replace], ["f3", FindNext], ["shift-f3", FindPrevious],
			["secondary-g", GoToLine], ["ctrl-g", GoToLine]
		];
		for (b in list)
			k.bind(b[0], b[1], ed);
		// (by words: Control elsewhere, Option on a Mac; both bound, a Mac's Control+arrows being the system's)
		for (m in ["ctrl", "alt"]) {
			k.bind('$m-left', MoveWordLeft, ed).bind('$m-right', MoveWordRight, ed);
			k.bind('$m-shift-left', SelectWordLeft, ed).bind('$m-shift-right', SelectWordRight, ed);
			k.bind('$m-backspace', DeleteWordLeft, ed).bind('$m-delete', DeleteWordRight, ed);
		}
		// (a Mac's Command+arrows: the line's and the file's ends)
		k.bind("cmd-left", MoveLineStart, ed).bind("cmd-right", MoveLineEnd, ed).bind("cmd-up", MoveDocStart, ed).bind("cmd-down", MoveDocEnd, ed);
		k.bind("cmd-shift-left", SelectLineStart, ed).bind("cmd-shift-right", SelectLineEnd, ed);
		k.bind("enter", FindNext, find).bind("shift-enter", FindPrevious, find).bind("f3", FindNext, find).bind("shift-f3", FindPrevious, find);
		k.bind("escape", ClosePanel, find).bind("secondary-f", Find, find).bind("secondary-h", Replace, find).bind("secondary-alt-enter", ReplaceAll, find);
	}
}
