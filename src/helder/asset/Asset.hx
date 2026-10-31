package helder.asset;

#if macro
import haxe.macro.Expr;
#else
import haxe.Exception;
import haxe.coro.IContinuation;
import helder.async.Async;
import helder.view.graph.Awaitable.Later;
import helder.view.graph.Graph;
import helder.view.graph.Node;
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
//
// The handle is a node of helder.view's graph (an async memo, DESIGN.md
// 2): read() reads it, tracked, as markup does with the handle itself
// (<image src={icon}/>, a Read prop): pending while it loads (a <Loading>
// boundary above shows its fallback on its first load), the AssetError
// after a failure (an <Errored>'s). A reload's new value is pending in turn
// (Graph.isPending says so), the last one kept meanwhile.
//
// Under `helder dev` the files are read from disk and watched: a change is
// sent to the running program, which loads it again and puts it behind
// the same handle, the engine's objects swapped in place (an Image's
// pixels, a FontFile's glyphs, a Model's meshes and materials: what draws
// them shows the new ones) and its readers run again.
//
// Loads advance on the main thread's loop (helder.async: App.run turns it;
// Assets.poll turns it for a program with a loop of its own).
class Asset<T> #if !macro implements helder.view.graph.Read.Reader<T> #end {
	#if !macro
	public final key:String;
	public var state(default, null):AssetState = Loading;
	public var ready(get, never):Bool;
	// how much of its file is here: the bytes received, and how many
	// there will be (0 while that is not known: a response that does not
	// say); on the web as they arrive, elsewhere once read. A group's
	// progress (AssetGroup) weighs its assets by them.
	public var bytesLoaded(default, null):Int = 0;
	public var bytesTotal(default, null):Int = 0;

	var current:Null<T> = null;
	final waiting:Array<IContinuation<T>> = [];
	// (the graph's node: the value, or while it loads (a reload too) an
	// answer later, each run its own; asked: a reload's question)
	final node:Node<T>;
	final asks:Array<Later<T>> = [];
	var reloading = false;
	final asked:Node<Int>;

	@:noCompletion public function new(key:String) {
		this.key = key;
		asked = Node.signal(0, {ownedWrite: true});
		// (of no owner: a handle outlives what reads it; every answer a change, a reload's object the same one)
		node = Graph.runWithOwner(null, () -> Node.computed(cast ((_:Null<T>) -> {
			asked.read();
			if (reloading || state == Loading) {
				var l = new Later<T>();
				asks.push(l);
				return (l : Dynamic);
			}
			return switch state {
				case Failed(error): throw new AssetError(key, error);
				case _: (current : Dynamic);
			}
		} : Null<T>->Dynamic), {equals: (_, _) -> false}, false));
	}

	// (the answers asked for: v, or the error)
	function answer(v:Null<T>, error:Null<AssetError>) {
		var ls = asks.copy();
		asks.resize(0);
		for (l in ls)
			if (error != null) l.reject(error) else l.resolve(v);
	}

	inline function get_ready():Bool
		return state == Ready;

	// the value, tracked (Reader): pending while it loads, the AssetError once failed
	public function read():T
		return node.read();

	// the value if it is here (not tracked, never throws), else null
	public function peek():Null<T>
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

	// (its file's bytes, as they arrive: Files.read's)
	@:noCompletion public function progressed(loaded:Int, total:Int) {
		bytesLoaded = loaded;
		bytesTotal = total > 0 ? total : bytesTotal;
		Assets.changed();
	}

	// the value arrived (again: a reload's, the readers told)
	@:noCompletion public function resolve(v:T) {
		current = v;
		state = Ready;
		if (bytesTotal < bytesLoaded) bytesTotal = bytesLoaded;
		Assets.changed();
		var w = waiting.copy();
		waiting.resize(0);
		for (c in w)
			Async.resumeLater(c, v, null);
		reloading = false;
		// (nothing asked: the node asks again, the value its answer)
		if (asks.length == 0) asked.update(n -> n + 1) else answer(v, null);
	}

	@:noCompletion public function fail(error:String) {
		state = Failed(error);
		Assets.changed();
		var w = waiting.copy();
		waiting.resize(0);
		for (c in w)
			Async.resumeLater(c, null, new AssetError(key, error));
		answer(null, new AssetError(key, error));
	}

	// (a reload begins: a new value on its way; or ends having kept the last value)
	@:noCompletion public function refresh(on:Bool) {
		if (on == reloading) return;
		reloading = on;
		if (on) asked.update(n -> n + 1) else answer(current, null);
	}

	public function toString():String
		return 'Asset(' + key + ', ' + state + ')';
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

	// a sound file's bytes (WAV or Ogg Vorbis): helder.os.audio.Sound.decode
	// decodes them whole (effects), Sfx.music streams Vorbis (music)
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
// an asset that did not load
class AssetError extends Exception {
	public final key:String;

	public function new(key:String, error:String) {
		super('$key: $error');
		this.key = key;
	}
}
#end
