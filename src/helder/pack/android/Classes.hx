package helder.pack.android;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;

// Which of Glue's Java classes an Android build needs, for the APK
// (helder.cli.Android): `--macro helder.pack.android.Classes.write("<file>")`
// writes {"dex", "views"} once the program is generated (after dead code
// elimination, when the build has it):
// - dex: a class marked @:helder.android.dex is in it (helder.os.android.Glue:
//   Java's listeners; a text input's TextWatcher too);
// - views: the program makes an instance of a class marked
//   @:helder.android.views (helder.ui.native.NativeHost: Android's views as
//   the activity's content), which needs org.hxmc.Activity: its window
//   draws views, not the program's surface. Being in the program is not
//   enough: every ui program has NativeHost (its native text editors), a
//   dev build every class it typed, and a drawn window needs
//   NativeActivity's surface.
class Classes {
	public static function write(file:String) {
		Context.onGenerate(types -> {
			var dex = false, views = false;
			var marked = new Map<String, Bool>();
			for (t in types)
				switch t {
					case TInst(c, _):
						var m = c.get().meta;
						if (m.has(":helder.android.dex")) dex = true;
						if (m.has(":helder.android.views")) marked.set(c.toString(), true);
					case _:
				}
			if (marked.keys().hasNext()) {
				function scan(e:TypedExpr) {
					if (views) return;
					switch e.expr {
						case TNew(c, _, _) if (marked.exists(c.toString())): views = true;
						case _: haxe.macro.TypedExprTools.iter(e, scan);
					}
				}
				function fields(c:ClassType) {
					for (f in c.statics.get().concat(c.fields.get())) {
						var e = f.expr();
						if (e != null) scan(e);
					}
					if (c.constructor != null) {
						var e = c.constructor.get().expr();
						if (e != null) scan(e);
					}
					if (c.init != null) scan(c.init);
				}
				for (t in types)
					switch t {
						case TInst(c, _) if (!views): fields(c.get());
						case _:
					}
			}
			sys.io.File.saveContent(file, haxe.Json.stringify({dex: dex || views, views: views}));
		});
	}
}
#end
