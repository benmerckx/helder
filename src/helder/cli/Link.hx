package helder.cli;

import sys.FileSystem;
import sys.io.File;

// A file at another path with the same content: a symbolic link (relative,
// so the tree can move), else a hard link, else a copy. Left alone while
// its content is the file's (a link is; a hard link stops being when an
// editor saves by renaming over the file, a copy when it is edited), made
// again otherwise.
class Link {
	// how `to` was made: "symlink", "hardlink", "copy", or "kept"
	public static function make(from:String, to:String):String {
		var content = File.getBytes(from);
		if (FileSystem.exists(to) && File.getBytes(to).compare(content) == 0) return "kept";
		// (also a dangling link, which FileSystem.exists does not see)
		try FileSystem.deleteFile(to) catch (_:Dynamic) {}
		if (symlink(relative(from, haxe.io.Path.directory(to)), to)) return "symlink";
		if (hardlink(from, to)) return "hardlink";
		File.saveBytes(to, content);
		return "copy";
	}

	// `path` as seen from the directory `dir` (both relative to the working directory)
	public static function relative(path:String, dir:String):String {
		var a = norm(path), b = norm(dir);
		var i = 0;
		while (i < a.length - 1 && i < b.length && a[i] == b[i]) i++;
		return [for (_ in i...b.length) ".."].concat(a.slice(i)).join("/");
	}

	static function norm(p:String):Array<String>
		return [for (s in p.split("\\").join("/").split("/")) if (s != "" && s != ".") s];

	static function symlink(target:String, path:String):Bool {
		#if (target.name == "hxmc")
		if (hxmc.unsafe.Mem.os() == 2)
			// (SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE: developer mode, else it fails)
			return hxmc.unsafe.Arena.scopedValue(a -> Kernel32.CreateSymbolicLinkW(a.wstring(path), a.wstring(target.split("/").join("\\")), 2)) != 0;
		return hxmc.unsafe.Arena.scopedValue(a -> Posix.symlink(a.cstring(target), a.cstring(path))) == 0;
		#else
		return false;
		#end
	}

	static function hardlink(target:String, path:String):Bool {
		#if (target.name == "hxmc")
		if (hxmc.unsafe.Mem.os() == 2)
			return hxmc.unsafe.Arena.scopedValue(a -> Kernel32.CreateHardLinkW(a.wstring(path), a.wstring(target), hxmc.unsafe.Ptr.nil())) != 0;
		return hxmc.unsafe.Arena.scopedValue(a -> Posix.link(a.cstring(target), a.cstring(path))) == 0;
		#else
		return false;
		#end
	}
}

#if (target.name == "hxmc")
@:hxmc.c private extern class Posix {
	static function symlink(target:hxmc.unsafe.Ptr, path:hxmc.unsafe.Ptr):Int;
	static function link(target:hxmc.unsafe.Ptr, path:hxmc.unsafe.Ptr):Int;
}

@:hxmc.c @:hxmc.lib("kernel32") private extern class Kernel32 {
	static function CreateSymbolicLinkW(path:hxmc.unsafe.Ptr, target:hxmc.unsafe.Ptr, flags:Int):Int;
	static function CreateHardLinkW(path:hxmc.unsafe.Ptr, target:hxmc.unsafe.Ptr, security:hxmc.unsafe.Ptr):Int;
}
#end
