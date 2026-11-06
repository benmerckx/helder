// actions' namespace is an identifier (in Haxe: RejectActionsNamespace.hx).
// expect: actions: the namespace "view er" is not an identifier (letters, digits and _)
import {actions} from "helder/ui/actions";

export const Viewer = actions("view er", {
	next() {},
});
