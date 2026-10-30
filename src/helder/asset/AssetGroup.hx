package helder.asset;

import helder.asset.Asset.AssetError;
import helder.view.graph.Node;

// Assets loaded together, for a loading screen: what a screen needs before
// it shows (its models, textures, fonts), the rest after.
//
//   final menu = new AssetGroup([Asset.font("fonts/Inter.ttf"), Asset.model("ship.glb"), Asset.image("sky.jpg")]);
//
//   // markup: a bar, and the screen once all are here
//   <view width={(menu.progress() * 100) + "%"} height={2}/>
//   <Show when={menu.done()}>...</Show>
//
//   // a coroutine: once all are here (an AssetError if one failed)
//   menu.load();
//
// progress() goes from 0 to 1, by bytes: each asset weighs its file's
// size (Asset.bytesTotal: on the web as soon as its response says it,
// else, until then, the others' mean), its part the bytes received
// (decoding after: a loaded asset's part is whole once it is ready). It
// never goes back (a size learnt late would otherwise move it), and is 1
// once all are ready. Tracked (progress(), done(), failed(): helder.view's
// graph, read in markup, a memo or an effect) or not (fraction, ready,
// error: the frame loop). The group is also a Reader of its progress
// (read(): pending until all are here: a <Loading> boundary above it shows
// its fallback meanwhile).
class AssetGroup implements helder.view.graph.Read.Reader<Float> {
	public final assets:Array<Asset<Dynamic>>;
	// (untracked) all ready; the share loaded, from 0 to 1; the first failure
	public var ready(default, null) = false;
	public var fraction(default, null) = 0.0;
	public var error(default, null):Null<AssetError> = null;

	final shown:Node<Float>;
	final complete:Node<Bool>;
	final broken:Node<Null<AssetError>>;
	var unwatch:Null<Void->Void> = null;

	public function new(assets:Array<Asset<Dynamic>>) {
		this.assets = assets;
		shown = Node.signal(0.0, {ownedWrite: true});
		complete = Node.signal(false, {ownedWrite: true});
		broken = Node.signal((null : Null<AssetError>), {ownedWrite: true});
		measure();
		if (!ready && error == null) unwatch = Assets.watch(measure);
	}

	// a group of these and other's assets (each once)
	public function and(other:AssetGroup):AssetGroup
		return new AssetGroup(assets.concat([for (a in other.assets) if (assets.indexOf(a) < 0) a]));

	// (tracked) the share loaded, 0 to 1
	public function progress():Float
		return shown.read();

	// (tracked) whether all are here
	public function done():Bool
		return complete.read();

	// (tracked) the first asset that failed to load, if one did
	public function failed():Null<AssetError>
		return broken.read();

	// (Reader) the progress, pending until all are here; the first failure thrown
	public function read():Float {
		for (a in assets)
			a.read();
		return progress();
	}

	public function peek():Float
		return fraction;

	// once all are here (at once if they are); an AssetError if one failed
	@:coroutine public function load():Void {
		for (a in assets)
			a.load();
	}

	// how many are ready, of how many
	public function count():{ready:Int, of:Int} {
		var n = 0;
		for (a in assets)
			if (a.ready) n++;
		return {ready: n, of: assets.length};
	}

	// what the bytes say, after each change to a load (Assets.changed)
	function measure() {
		var known = 0.0, sized = 0, all = true;
		for (a in assets) {
			if (a.bytesTotal > 0) {
				known += a.bytesTotal;
				sized++;
			}
			switch a.state {
				case Ready:
				case Failed(e):
					all = false;
					if (error == null) error = new AssetError(a.key, e);
				case Loading:
					all = false;
			}
		}
		var mean = sized == 0 ? 1.0 : known / sized, weight = 0.0, got = 0.0;
		for (a in assets) {
			var w = a.bytesTotal > 0 ? a.bytesTotal : mean;
			weight += w;
			// (received, not yet decoded: most of its part)
			got += a.ready ? w : a.bytesTotal > 0 ? w * 0.95 * Math.min(1, a.bytesLoaded / a.bytesTotal) : 0;
		}
		var f = all || weight <= 0 ? 1.0 : got / weight;
		if (f > fraction) fraction = f;
		ready = all;
		shown.write(fraction);
		if (all) complete.write(true);
		if (error != null) broken.write(error);
		if ((all || error != null) && unwatch != null) {
			unwatch();
			unwatch = null;
		}
	}
}
