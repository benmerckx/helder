package asset;

import haxe.io.Bytes;
import helder.async.Async;
import helder.asset.Asset;
import helder.asset.Assets;
import helder.image.Image;
import helder.test.Test;
import helder.view.Reactive.*;

// helder.asset in a program (natively: the files in the executable's
// data; as wasm32-wasi beside the module, fetched): the bundle has what
// code that runs names and nothing else (Bundle's markers), a handle per
// path loaded by a coroutine, several at once, a failure, value a signal
function tests() {
	// (natively the executable's resources; as wasm32-wasi the files are
	// beside the module, which the asset lane checks: bundled() is null)
	describe("the bundle", () -> {
		test("the files code that runs names, sorted", () -> {
			var b = Assets.bundled();
			if (b == null) return;
			assert(b.contains("asset/files/kept.txt"), b.join(", "));
			assert(b.contains("asset/files/pixels.png"), b.join(", "));
			var sorted = b.copy();
			sorted.sort(Reflect.compare);
			equals(b, sorted);
		});
		test("not one only code that nothing reaches names", () -> {
			var b = Assets.bundled();
			if (b == null) return;
			assert(!b.contains("asset/files/dropped.txt"), b.join(", "));
		});
	});
	describe("load", () -> {
		test("a file's bytes, a handle per path", async(() -> {
			var a = Asset.bytes("asset/files/kept.txt");
			equals(Asset.bytes("asset/files/kept.txt"), a);
			var b = a.load();
			equals(b.toString(), "kept by the tests\n");
			assert(a.ready);
			equals(a.peek(), b);
			equals(a.value, b);
		}));
		test("an image, decoded (a PNG as a job)", async(() -> {
			var img:Image = Asset.image("asset/files/pixels.png").load();
			equals([img.width, img.height], [2, 2]);
			equals([for (i in 0...16) img.pixels.get(i)], [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 128]);
		}));
		test("several at once: tasks, Async.all", async(() -> {
			var got = Async.scope(task -> Async.all([
				task.async(_ -> Asset.bytes("asset/files/kept.txt").load().length),
				task.async(_ -> Asset.bytes("asset/files/pixels.png").load().length)
			]));
			equals(got, [18, 76]);
		}));
		test("a failure: load throws, value too", async(() -> {
			// (the text file is no image)
			var a = Asset.image("asset/files/kept.txt");
			var e:Dynamic = throwsAsync(() -> a.load());
			assert(e is AssetError, Std.string(e));
			assert(a.state.match(Failed(_)));
			assert(throws(() -> a.value) is AssetError);
		}));
	});
	describe("the handle", () -> {
		test("value before it is here: AssetPending; peek null", () -> {
			var a = new Asset<Int>("later");
			equals(a.peek(), null);
			var e = throws(() -> a.value);
			assert(e is AssetPending);
			equals((e : AssetPending).asset, cast a);
		});
		test("load suspends until it is resolved", async(() -> {
			var a = new Asset<Int>("later");
			var t = Async.launch(_ -> a.load());
			Async.yield();
			assert(!a.ready);
			a.resolve(4);
			equals(t.await(), 4);
		}));
		test("value is a signal: its readers run again on a reload", () -> {
			var a = new Asset<String>("text"), seen = [];
			a.resolve("one");
			var dispose = root(d -> {
				effect(() -> seen.push(a.value));
				d;
			});
			a.resolve("two");
			dispose();
			a.resolve("three");
			equals(seen, ["one", "two"]);
		});
	});
}

// (named, never called: its file is not bundled)
function unused():Asset<Bytes>
	return Asset.bytes("asset/files/dropped.txt");
