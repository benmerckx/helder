package helder.os.cocoa;

import helder.os.objc.*;
import hxmc.unsafe.*;

// macOS's open panel (NSOpenPanel), modal (runModal): files of the filters'
// extensions (setAllowedFileTypes:), one, not folders; its URL's path, null
// when cancelled.
@:hxmc.unsafe(gc)
class OpenPanel {
	// (made and set up, not shown: the tests' check)
	public static function make(title:String, filters:Array<{name:String, extensions:Array<String>}>):Ptr {
		var panel = Msg.id(ObjC.cls("NSOpenPanel"), ObjC.sel("openPanel"));
		if (panel.isNull()) return panel;
		var t = ObjC.str(title);
		Msg.vPtr(panel, ObjC.sel("setMessage:"), t);
		ObjC.release(t);
		Msg.vBool(panel, ObjC.sel("setCanChooseFiles:"), true);
		Msg.vBool(panel, ObjC.sel("setCanChooseDirectories:"), false);
		Msg.vBool(panel, ObjC.sel("setAllowsMultipleSelection:"), false);
		var types = Msg.id(Msg.id(ObjC.cls("NSMutableArray"), ObjC.sel("alloc")), ObjC.sel("init"));
		for (f in filters)
			for (e in f.extensions) {
				var s = ObjC.str(e);
				Msg.vPtr(types, ObjC.sel("addObject:"), s);
				ObjC.release(s);
			}
		if (filters.length > 0) Msg.vPtr(panel, ObjC.sel("setAllowedFileTypes:"), types);
		ObjC.release(types);
		return panel;
	}

	public static function open(title:String, filters:Array<{name:String, extensions:Array<String>}>):Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var panel = make(title, filters);
		var path:Null<String> = null;
		// (NSModalResponseOK: 1)
		if (!panel.isNull() && Msg.i(panel, ObjC.sel("runModal")).toInt() == 1) {
			var urls = Msg.id(panel, ObjC.sel("URLs"));
			if (Msg.i(urls, ObjC.sel("count")).toInt() > 0) path = ObjC.string(Msg.id(Msg.idInt(urls, ObjC.sel("objectAtIndex:"), 0), ObjC.sel("path")));
		}
		Runtime.objc_autoreleasePoolPop(pool);
		return path;
	}
}
