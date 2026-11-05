package helder.ui.native.appkit;

import helder.os.objc.*;
import helder.ui.*;
import hxmc.unsafe.*;

// The fonts of macOS's own views (MacViews): an NSFont for a ui Font.
class AppKitBackend {
	@:allow(helder.ui) static function font(f:Font):Ptr {
		var name = ObjC.str(f.family);
		var nf = AkMsg.idPtrFloat(ObjC.cls("NSFont"), ObjC.sel("fontWithName:size:"), name, f.size);
		ObjC.release(name);
		if (nf.isNull()) nf = AkMsg.idFloat(ObjC.cls("NSFont"), ObjC.sel("systemFontOfSize:"), f.size);
		var fm = AkMsg.id(ObjC.cls("NSFontManager"), ObjC.sel("sharedFontManager"));
		// (NSFontTraitMask: italic 1, bold 2)
		if (f.weight >= 600) nf = AkMsg.idPtrInt(fm, ObjC.sel("convertFont:toHaveTrait:"), nf, 2);
		if (f.italic) nf = AkMsg.idPtrInt(fm, ObjC.sel("convertFont:toHaveTrait:"), nf, 1);
		return nf;
	}
}
