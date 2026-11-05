package helder.os;

import hxmc.unsafe.*;

// The app registered as one that opens files of some types (the system's
// "Open with"), for this user: Windows' HKCU\Software\Classes (a ProgID
// whose shell\open\command runs the program with the file, each
// extension's OpenWithProgids naming it, the application's SupportedTypes;
// the shell told: SHChangeNotify), Linux's
// ~/.local/share/applications/<id>.desktop (MimeType, Exec with %F;
// update-desktop-database run where there is one). macOS's are the app
// bundle's Info.plist (CFBundleDocumentTypes: helder build --app), not
// written here. What it wrote: paths, or registry keys.
class FileTypes {
	public static function register(id:String, name:String, exe:String, types:Array<{mime:String, extensions:Array<String>}>):Array<String>
		return if (Mem.os() == 2) windows(id, name, exe, types) else if (Mem.os() == 0 && Mem.target() < 9) linux(id, name, exe, types) else [];

	// (the registry's values under HKEY_CURRENT_USER, REG_SZ)
	static function windows(id:String, name:String, exe:String, types:Array<{mime:String, extensions:Array<String>}>):Array<String> {
		var progId = id + ".file", base = "Software\\Classes\\", done = [];
		function set(key:String, value:Null<String>, data:String)
			Arena.scoped(a -> {
				var hk:Ptr<Ptr> = a.alloc(8);
				// (HKEY_CURRENT_USER 0x80000001; KEY_WRITE 0x20006)
				if (helder.os.win32.User32.Advapi32.RegCreateKeyExW(Ptr.ofI64((0x80000001 : Int64)), a.wstring(key), 0, Ptr.nil(), 0, 0x20006, Ptr.nil(), hk, Ptr.nil()) != 0) return;
				var w:Ptr<UInt16> = a.wstring(data);
				helder.os.win32.User32.Advapi32.RegSetValueExW(hk.value, value == null ? Ptr.nil() : a.wstring(value), 0, 1, cast w, 2 * (data.length + 1));
				helder.os.win32.User32.Advapi32.RegCloseKey(hk.value);
				done.push("HKCU\\" + key + (value == null ? "" : "\\" + value));
			});
		var command = '"$exe" "%1"';
		set(base + progId, null, name);
		set(base + progId + "\\shell\\open\\command", null, command);
		var app = base + "Applications\\" + haxe.io.Path.withoutDirectory(exe);
		set(app + "\\shell\\open\\command", null, command);
		for (t in types)
			for (e in t.extensions) {
				set(base + "." + e + "\\OpenWithProgids", progId, "");
				set(app + "\\SupportedTypes", "." + e, "");
			}
		Shell32Notify.SHChangeNotify(0x08000000, 0, Ptr.nil(), Ptr.nil()); // (SHCNE_ASSOCCHANGED)
		return done;
	}

	static function linux(id:String, name:String, exe:String, types:Array<{mime:String, extensions:Array<String>}>):Array<String> {
		var home = Sys.getEnv("XDG_DATA_HOME") ?? (Sys.getEnv("HOME") + "/.local/share");
		var dir = home + "/applications";
		try sys.FileSystem.createDirectory(dir) catch (_:Dynamic) {}
		var path = '$dir/$id.desktop';
		var mimes = [for (t in types) t.mime];
		sys.io.File.saveContent(path, [
			"[Desktop Entry]",
			"Type=Application",
			'Name=$name',
			'Exec="${exe.split("\"").join("\\\"")}" %F',
			"Terminal=false",
			"Categories=Graphics;Viewer;",
			'MimeType=${mimes.join(";")};',
			""
		].join("\n"));
		for (bin in ["/usr/bin/update-desktop-database", "/usr/local/bin/update-desktop-database"])
			if (sys.FileSystem.exists(bin)) {
				Sys.command(bin, [dir]);
				break;
			}
		return [path];
	}
}

@:hxmc.c @:hxmc.lib("shell32") extern class Shell32Notify {
	static function SHChangeNotify(event:Int, flags:Int, a:Ptr, b:Ptr):Void;
}
