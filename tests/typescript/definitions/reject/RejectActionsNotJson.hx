// an action's arguments are read from a JSON keymap (in TypeScript: actions-not-json.ts).
// expect: actions: viewer::Run's argument callback cannot be read from JSON: a function (JSON-readable: numbers, strings, booleans, and arrays and structures of these)
import helder.ui.actions.Actions;

enum ViewerAction {
	Next;
	Run(callback:Void->Void);
}

class RejectActionsNotJson {
	static function main() {
		actions("viewer", ViewerAction);
	}
}
