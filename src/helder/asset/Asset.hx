package helder.asset;

#if macro
import haxe.macro.Expr;
#else
import haxe.Exception;
import haxe.coro.IContinuation;
import helder.async.Async;
import helder.view.Signal.SignalBase;
#end

// A file of the program, by its path (AssetPath): an image, a font, a model,
// a sound or bytes. The path is checked when compiling (the file there, in
// that case) and the file goes with every build that still uses it after
// dead code elimination (Bundle: the executable's data on desktop, the APK's
// assets/ on Android, the app's on iOS, beside the page on the web).
//
//   @:coroutine static function start() {
//     var ship = Asset.model("models/ship.glb").load();  // suspends until loaded
//     ship.instantiate(world, device);
//   }
//
// A handle is returned at once, its load started (one per path and kind:
// the same handle each time); load() suspends the calling coroutine until
// it is ready (at once if it is) and throws if it failed. Several at once
// with tasks: task.async(_ -> a.load()), then Async.all. Without
// suspending (the frame loop): ready, peek() (null until then), state.
// value is the loaded value as a signal (helder.view): read in markup or a
// memo it is tracked; read before it is ready it throws AssetPending (inside
// a <Loading> boundary: that content waits for it), after a failure the
// AssetError.
//
// Under `helder dev` the files are read from disk and watched: a change is
// sent to the running program, which loads it again and puts it behind
// the same handle, the engine's objects swapped in place (an Image's
// pixels, a FontFile's glyphs, a Model's meshes and materials: what draws
// them shows the new ones) and value's readers run again.
//
// Loads advance on the main thread's loop (helder.async: App.run turns it;
// Assets.poll turns it for a program with a loop of its own).
class Asset<T> #if !macro extends SignalBase #end {
	#if !macro
	public final key:String;
	public var state(default, null):AssetState = Loading;
	public var ready(get, never):Bool;
	public var value(get, never):T;

	var current:Null<T> = null;
	final waiting:Array<IContinuation<T>> = [];

	@:noCompletion public function new(key:String) {
		this.key = key;
	}

	// (tracked: a reader that waits for it runs again once it is)
	function get_ready():Bool {
		track();
		return state == Ready;
	}

	// the value, tracked; AssetPending while loading, the AssetError once failed
	function get_value():T {
		track();
		return switch state {
			case Ready: current;
			case Loading: throw new AssetPending(this);
			case Failed(error): throw new AssetError(key, error);
		}
	}

	// the value if it is here (not tracked, never throws), else null
	public inline function peek():Null<T>
		return current;

	// the value, once loaded: the calling coroutine waits for it (an
	// AssetError if it failed)
	@:coroutine public function load():T {
		switch state {
			case Ready:
				return current;
			case Failed(error):
				throw new AssetError(key, error);
			case Loading:
		}
		return Async.suspendCancellable(cont -> {
			waiting.push(cont);
			return _ -> waiting.remove(cont);
		});
	}

	// the value arrived (again: a reload's, the readers told)
	@:noCompletion public function resolve(v:T) {
		current = v;
		state = Ready;
		var w = waiting.copy();
		waiting.resize(0);
		for (c in w)
			Async.resumeLater(c, v, null);
		notify();
	}

	@:noCompletion public function fail(error:String) {
		state = Failed(error);
		var w = waiting.copy();
		waiting.resize(0);
		for (c in w)
			Async.resumeLater(c, null, new AssetError(key, error));
		notify();
	}

	public function toString():String
		return 'Asset($key, $state)';
	#end

	// an image (helder.image.Image): PNG (decoded as a job: ImageJobs), JPEG, GIF, WebP
	public static macro function image(path:String):Expr
		return AssetMacro.handle(path, "image");

	// a font (helder.text.FontFile, its first face; added to
	// helder.text.SystemFonts: ui finds it by its family's name)
	public static macro function font(path:String):Expr
		return AssetMacro.handle(path, "font");

	// a glTF model (helder.scene.render.Model, its names typed from the
	// file as Model.of types them: model.nodes.LeftHand)
	public static macro function model(path:String):Expr
		return AssetMacro.model(path);

	// a sound file's bytes (no decoding yet: helder.os.audio plays samples)
	public static macro function sound(path:String):Expr
		return AssetMacro.handle(path, "sound");

	// a file's bytes (haxe.io.Bytes)
	public static macro function bytes(path:String):Expr
		return AssetMacro.handle(path, "bytes");

	// the file's bytes built into the code itself (no bundle, nothing to
	// load: PackedModel.read(Asset.embed("level.hxm3d"), device)); for small
	// files, read when compiling and not reloaded
	public static macro function embed(path:String):Expr
		return AssetMacro.embed(path);
}

enum AssetState {
	Loading;
	Ready;
	Failed(error:String);
}

#if !macro
// an asset's value read before it was loaded (Asset.value): a <Loading>
// boundary waits for asset; elsewhere a mistake (load() or peek() then)
class AssetPending extends Exception {
	public final asset:Asset<Dynamic>;

	public function new(asset:Asset<Dynamic>) {
		super('${asset.key}: not loaded yet (read value inside <Loading>, or load() in a coroutine, peek() in the frame loop)');
		this.asset = asset;
	}
}

// an asset that did not load
class AssetError extends Exception {
	public final key:String;

	public function new(key:String, error:String) {
		super('$key: $error');
		this.key = key;
	}
}
#end
