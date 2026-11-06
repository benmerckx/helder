// a namespace is declared once in a program (in Haxe: RejectActionsTwice.hx).
// expect: actions: the namespace viewer is declared twice (once in a program)
import {actions} from "helder/ui/actions";

export const Viewer = actions("viewer", {
	next() {},
});
export const Picker = actions("viewer", {
	close() {},
});
