package hxmc.ui.draw;

import hxmc.unsafe.*;

// The browser's side of the accessibility tree (WebAssembly): imports of the
// module "hxmc_ui", which packages/ui/imports.mjs provides. UiWindow sends
// each change of its tree (AccessTree.changesJson) for the mirror inside
// its canvas and polls the actions assistive technology asks for.
@:hxmc.c @:hxmc.lib("hxmc_ui") extern class WebAccess {
	// an update (JSON) of the tree of the window whose canvas is that handle
	static function access_update(canvas:Int, json:CString):Void;
	// the next action into p (the node id, the AccessAction); 0: none
	static function access_action(p:Ptr<Int32>):Int;
}
