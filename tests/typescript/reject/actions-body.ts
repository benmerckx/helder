// An action with arguments returns them as an object: what TypeScript
// types its value as (a type has no parameter names).
// expect: actions-body.ts:8: TSHX001: actions: zoomTo's body is `return { percent };`
import {actions} from "helder/ui/actions";

export const Viewer = actions("viewer", {
	next() {},
	zoomTo(percent: number) {},
});
