package helder.cli;

// page.html's text, built in (a module of its own: the macro's context
// types this, not Page and what it uses)
class PageTemplate {
	public static macro function text():haxe.macro.Expr
		return macro $v{sys.io.File.getContent(haxe.macro.Context.resolvePath("helder/cli/page.html"))};
}
