package helder.pack.android;

#if macro
import haxe.macro.Context;

// Which of Glue's Java classes an Android build needs, for the APK
// (helder.cli.Android): `--macro helder.pack.android.Classes.write("<file>")`
// writes {"dex", "views"} once the program is generated (after dead code
// elimination): dex when a class marked @:helder.android.dex is in it
// (helder.os.android.Glue: Java's listeners), views when one marked
// @:helder.android.views is (Android's views as the activity's content:
// helder.ui.native.android), which needs classes.dex and org.hxmc.Activity.
class Classes {
	public static function write(file:String) {
		Context.onGenerate(types -> {
			var dex = false, views = false;
			for (t in types)
				switch t {
					case TInst(c, _):
						var m = c.get().meta;
						if (m.has(":helder.android.dex")) dex = true;
						if (m.has(":helder.android.views")) views = true;
					case _:
				}
			sys.io.File.saveContent(file, haxe.Json.stringify({dex: dex || views, views: views}));
		});
	}
}
#end
