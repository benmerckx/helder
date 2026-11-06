// a namespace is declared once in a program (in TypeScript: actions-twice.ts).
// expect: actions: the namespace viewer is declared twice (once in a program)
import helder.ui.actions.Actions;

enum ViewerAction {
	Next;
}

enum PickerAction {
	Close;
}

class RejectActionsTwice {
	static function main() {
		actions("viewer", ViewerAction);
		actions("viewer", PickerAction);
	}
}
