// an action's arguments are read from a JSON keymap (in Haxe: RejectActionsNotJson.hx).
// expect: actions: viewer::Run's argument callback cannot be read from JSON: a function (JSON-readable: numbers, strings, booleans, and arrays and structures of these)
import {actions} from "helder/ui/actions";

export const Viewer = actions("viewer", {
	next() {},
	run(callback: () => void) {
		return {callback};
	},
});
