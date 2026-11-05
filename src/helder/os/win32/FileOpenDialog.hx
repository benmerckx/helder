package helder.os.win32;

import hxmc.unsafe.*;

// Windows' common file dialog (IFileOpenDialog, through COM's vtables):
// the filters (COMDLG_FILTERSPEC), the title, Show over the owner window
// (modal: Windows' own loop meanwhile), the result's file system path
// (IShellItem.GetDisplayName). null: cancelled, or no dialog.
class FileOpenDialog {
	static final CLSID = Com.guid(0xDC1C5A9C, 0xE88A, 0x4DDE, [0xA5, 0xA1, 0x60, 0xF8, 0x2A, 0x20, 0xAE, 0xF7]);
	static final IID = Com.guid(0xD57C7288, 0xD4AD, 0x4768, [0xBE, 0x02, 0x9D, 0x96, 0x95, 0x32, 0xD9, 0x60]);

	// (made, its filters and title set, not shown: the tests' check that COM gives one)
	public static function make(title:String, filters:Array<{name:String, extensions:Array<String>}>):Ptr {
		Shell32Com.CoInitializeEx(Ptr.nil(), 2); // (COINIT_APARTMENTTHREADED; already: S_FALSE)
		var out:Ptr<Ptr> = LibC.malloc(8);
		out.value = Ptr.nil();
		var hr = Shell32Com.CoCreateInstance(CLSID, Ptr.nil(), 1, IID, out);
		var d = out.value;
		LibC.free(cast out);
		if (hr < 0 || d.isNull()) return Ptr.nil();
		Arena.scoped(a -> {
			if (filters.length > 0) {
				var spec:Ptr<Ptr> = a.alloc(16 * filters.length);
				for (i in 0...filters.length) {
					spec[2 * i] = a.wstring(filters[i].name);
					spec[2 * i + 1] = a.wstring([for (e in filters[i].extensions) "*." + e].join(";"));
				}
				IFileOpenDialog.SetFileTypes(d, filters.length, cast spec);
			}
			IFileOpenDialog.SetTitle(d, a.wstring(title));
		});
		return d;
	}

	public static function open(owner:Ptr, title:String, filters:Array<{name:String, extensions:Array<String>}>):Null<String> {
		var d = make(title, filters);
		if (d.isNull()) return null;
		var path:Null<String> = null;
		if (IFileOpenDialog.Show(d, owner) >= 0) {
			var item:Ptr<Ptr> = LibC.malloc(8);
			item.value = Ptr.nil();
			if (IFileOpenDialog.GetResult(d, item) >= 0 && !item.value.isNull()) {
				var name:Ptr<Ptr> = LibC.malloc(8);
				// (SIGDN_FILESYSPATH)
				if (IShellItem.GetDisplayName(item.value, 0x80058000, name) >= 0) {
					var w:Ptr<UInt16> = cast name.value, b = new StringBuf(), k = 0;
					while (w[k] != 0) {
						var c:Int = w[k++];
						if (c >= 0xD800 && c < 0xDC00) c = 0x10000 + ((c - 0xD800) << 10) + ((w[k++] : Int) - 0xDC00);
						b.addChar(c);
					}
					path = b.toString();
					Shell32Com.CoTaskMemFree(name.value);
				}
				LibC.free(cast name);
				Com.release(item.value);
			}
			LibC.free(cast item);
		}
		Com.release(d);
		return path;
	}
}

@:hxmc.c @:hxmc.lib("ole32") extern class Shell32Com {
	static function CoInitializeEx(reserved:Ptr, flags:Int):Int;
	static function CoCreateInstance(clsid:Ptr, outer:Ptr, context:Int, iid:Ptr, out:Ptr<Ptr>):Int;
	static function CoTaskMemFree(p:Ptr):Void;
}

// (IUnknown 0-2, IModalWindow's Show 3, then IFileDialog's)
@:build(helder.os.win32.Com.build())
class IFileOpenDialog {
	@:slot(3) static function Show(self:Ptr, owner:Ptr):Int;
	@:slot(4) static function SetFileTypes(self:Ptr, count:Int, specs:Ptr):Int;
	@:slot(17) static function SetTitle(self:Ptr, title:Ptr):Int;
	@:slot(20) static function GetResult(self:Ptr, item:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class IShellItem {
	@:slot(5) static function GetDisplayName(self:Ptr, sigdn:Int, name:Ptr<Ptr>):Int;
}
