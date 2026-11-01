package helder.os;

import helder.test.Test;

// A program on App's lifecycle and back (App.onBack, App.background,
// App.onForeground) links only its own system's libraries: this file's
// program starting at all is the test (natively: Linux's would not load
// with Android's libandroid.so). Type.resolveClass and Type.createInstance
// with a name known only at run time make hxmc keep the constructors and
// methods, called by name, of every class the program has, AndroidWindow's
// among them (what a game's save, haxe.Unserializer, does): their calls of
// Android's functions are behind a constant test, folded away elsewhere.
function tests() {
	test("App's lifecycle and back: the program starts, with only its system's libraries", () -> {
		var backs = 0;
		App.onBack = () -> {
			backs++;
			return true;
		};
		App.onForeground = () -> {};
		assert(!App.background);
		assert(App.back());
		equals(backs, 1);
		App.onBack = null;
		App.onForeground = null;
		// (never true: a name the program cannot know when compiled)
		var name = Sys.args().length > 1000 ? Sys.args()[0] : "helder.os.NoSuchClass";
		var c = Type.resolveClass(name);
		var o:Dynamic = c == null ? null : Sys.args().length > 1001 ? Type.createInstance(c, []) : Type.createEmptyInstance(c);
		if (o != null) Reflect.callMethod(o, Reflect.field(o, name), []);
		equals(o, null);
	});
}
