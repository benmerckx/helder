package helder.asset;

import helder.async.Async;
import helder.async.Node.Body;

// The program's assets: one handle per kind and path (Asset.image("a.png")
// twice is one load), each loaded by a task on the main thread's loop.
// Each kind's module (ImageAsset, FontAsset, BytesAsset, helder.scene's
// Model) gives its loader and how a reload's value takes the old one's
// place (swap: the old object changed in place and kept, or the new one).
// What else moves on: loads polled by a program (track, Model.load's).
class Assets {
	static final handles = new Map<String, Asset<Dynamic>>();
	static final reloads = new Map<String, Array<Void->Void>>();
	static final pending:Array<Void->Bool> = [];

	// the handle of key's asset of a kind, its load started when it is made
	// (load: the value from the bundle, or from disk under helder dev)
	@:noCompletion public static function handle<T>(kind:String, key:String, load:Body<T>, swap:(old:T, fresh:T) -> T):Asset<T> {
		var id = kind + ":" + key;
		var h:Null<Asset<T>> = cast handles.get(id);
		if (h != null) return h;
		var a = new Asset<T>(key);
		handles.set(id, a);
		start(a, load, null);
		#if hxmc.dev
		// (a change helder dev sends: loaded again, put behind the same handle)
		var list = reloads.get(key);
		if (list == null) reloads.set(key, list = []);
		list.push(() -> start(a, load, swap));
		DevAssets.listen();
		#end
		return a;
	}

	static function start<T>(a:Asset<T>, load:Body<T>, swap:Null<(old:T, fresh:T) -> T>) {
		if (swap != null) a.refresh(true);
		Async.launch(load).onCompletion((v, e) -> {
			if (e != null) {
				// (a reload that failed: the last value stays)
				if (swap != null) {
					DevAssets.log('${a.key} not reloaded: ${e.message}');
					a.refresh(false);
				} else a.fail(e.message);
				return;
			}
			var old = a.peek();
			a.resolve(swap != null && old != null ? swap(old, v) : v);
			if (swap != null) DevAssets.log('${a.key} reloaded');
		});
	}

	// key's file changed (helder dev): its handles loaded again; whether any is
	@:noCompletion public static function reload(key:String):Bool {
		var list = reloads.get(key);
		if (list == null) return false;
		for (f in list)
			f();
		return true;
	}

	// the key in an asset's marker (AssetMacro's: Bundle.marker)
	@:noCompletion public static function key(marker:String):String
		return marker.substring(17, marker.length - 1);

	// a load polled until it returns true (Model.load's fetch)
	public static function track(poll:Void->Bool) {
		if (!poll()) pending.push(poll);
	}

	// advances the loads (Stages.frame calls it): the polled ones, and the
	// main loop turned once without waiting where no App.run turns it (a
	// program's own loop, a test); the number of polled loads still going
	public static function poll():Int {
		var i = 0;
		while (i < pending.length)
			if (pending[i]()) pending.splice(i, 1) else i++;
		var l = helder.async.Driven.MainLoop.main;
		if (l != null && !l.turning) l.turn(0);
		return pending.length;
	}

	// the keys of the files built into this executable (desktop: its
	// resources, Bundle; the files the program uses after dead code
	// elimination, when helder's CLI built it), sorted; null elsewhere (the
	// files are beside it: the APK's, the app's, the page's)
	public static function bundled():Null<Array<String>> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi" && hxmc.target != "android-arm64" && hxmc.target != "android-x86_64" && hxmc.target != "ios-arm64" && hxmc.target != "ios-sim-arm64")
		var out = [for (n in hxmc.NativeResource.names()) if (StringTools.startsWith(n, Bundle.PREFIX)) n.substr(Bundle.PREFIX.length)];
		out.sort(Reflect.compare);
		return out;
		#else
		return null;
		#end
	}
}

// helder dev's side: the changes it sends (natively the devtools
// protocol's notification Assets.changed {key} on the dev connection; on the
// web the page's, from its WebSocket, which calls the module), in dev
// builds only
@:noCompletion class DevAssets {
	public static function log(s:String)
		Sys.stderr().writeString("helder.asset: " + s + "\n");

	#if hxmc.dev
	static var listening = false;

	static function changed(key:String)
		if (!Assets.reload(key)) log('$key changed: not loaded by this build');

	#if (hxmc.target == "wasm32-wasi")
	// (the page calls it when a file changed: the keys it has, taken)
	@:hxmc.callback static function webChanged():Int {
		var n;
		while ((n = DevWebAssets.asset_length()) >= 0) {
			var b = haxe.io.Bytes.alloc(n);
			hxmc.unsafe.Arena.scoped(a -> {
				var p = a.alloc(n + 1, 1);
				DevWebAssets.asset_take(p);
				hxmc.unsafe.BytesPtr.copyIn(b, 0, p, n);
			});
			changed(b.toString());
		}
		return 0;
	}
	#end

	public static function listen() {
		if (listening) return;
		listening = true;
		#if (hxmc.target == "wasm32-wasi")
		DevWebAssets.asset_register(hxmc.unsafe.Callback.addr(webChanged));
		#elseif (target.name == "hxmc")
		helder.devtools.Agent.method("Assets.changed", p -> {
			changed(p.key);
			return {};
		});
		#end
	}
	#end
}

#if (hxmc.dev && hxmc.target == "wasm32-wasi")
// the page's side under helder dev (page.html): the keys of the files that
// changed, in order, and the function it calls then (a @:hxmc.callback ():Int)
@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_dev") extern class DevWebAssets {
	static function asset_register(f:hxmc.unsafe.Ptr):Void;
	// the next key's UTF-8 length (-1: none), its bytes into p (then the next)
	static function asset_length():Int;
	static function asset_take(p:hxmc.unsafe.Ptr):Void;
}
#end
