package studio;

// What the studio knows of how it was built: helder's src/ it was built
// from (a project without helder in its package.json's dependencies is
// built with it: helder.cli.Entry's HELDER_SRC)
class BuildInfo {
	public static macro function helderSrc() {
		var hot = haxe.macro.Context.resolvePath("helder/dev/Hot.hx");
		var full = sys.FileSystem.fullPath(hot).split("\\").join("/");
		return macro $v{full.substr(0, full.length - "/helder/dev/Hot.hx".length)};
	}
}
