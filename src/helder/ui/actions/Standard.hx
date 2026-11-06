package helder.ui.actions;

import helder.ui.actions.Actions;

// StandardAction's actions, declared (standard::Quit, standard::Copy... in
// a keymap) before any space is looked up (Actions)
class Standard {
	static var space:Null<ActionSpace<StandardAction>> = null;

	public static function declare():ActionSpace<StandardAction> {
		if (space == null) space = actions("standard", StandardAction);
		return space;
	}
}
