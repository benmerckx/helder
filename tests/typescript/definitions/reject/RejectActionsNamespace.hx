// actions' namespace is an identifier (in TypeScript: actions-namespace.ts).
// expect: actions: the namespace "view er" is not an identifier (letters, digits and _)
import helder.ui.actions.Actions;

enum ViewerAction {
	Next;
}

class RejectActionsNamespace {
	static function main() {
		actions("view er", ViewerAction);
	}
}
