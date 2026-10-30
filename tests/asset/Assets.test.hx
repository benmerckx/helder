package asset;

import haxe.io.Bytes;
import helder.async.Async;
import helder.asset.Asset;
import helder.asset.Assets;
import helder.image.Image;
import helder.test.Test;
import helder.view.graph.Graph.*;

// helder.asset in a program (natively: the files in the executable's
// data; as wasm32-wasi beside the module, fetched): the bundle has what
// code that runs names and nothing else (Bundle's markers), a handle per
// path loaded by a coroutine, several at once, a failure, the handle a
// node of helder.view's graph (an async memo)
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
			flush();
			equals(untrack(a.read), b);
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
		test("a failure: load throws, read too", async(() -> {
			// (the text file is no image)
			var a = Asset.image("asset/files/kept.txt");
			var e:Dynamic = throwsAsync(() -> a.load());
			assert(e is AssetError, Std.string(e));
			assert(a.state.match(Failed(_)));
			flush();
			assert(throws(() -> untrack(a.read)) is AssetError);
		}));
	});
	describe("a group", () -> {
		test("its progress by bytes, done once all are here", async(() -> {
			var a = Asset.bytes("asset/files/kept.txt"), b = Asset.bytes("asset/files/pixels.png");
			var g = new helder.asset.AssetGroup([a, b]);
			g.load();
			assert(g.ready);
			equals(g.fraction, 1.0);
			equals([a.bytesLoaded, a.bytesTotal, b.bytesTotal], [18, 18, 76]);
			equals(g.count(), {ready: 2, of: 2});
			flush();
			equals(untrack(g.progress), 1.0);
			assert(untrack(g.done));
			equals(untrack(g.failed), null);
		}));
		test("a failure: its error, load throws", async(() -> {
			var g = new helder.asset.AssetGroup([Asset.bytes("asset/files/kept.txt"), Asset.image("asset/files/kept.txt")]);
			var e:Dynamic = throwsAsync(() -> g.load());
			assert(e is AssetError, Std.string(e));
			assert(!g.ready);
			flush();
			assert(untrack(g.failed) is AssetError);
			assert(!untrack(g.done));
		}));
	});
	describe("a font", () -> {
		test("its first face, added to the program's fonts", async(() -> {
			var f = Asset.font("text/var.ttf").load();
			assert(f.family != "", "a family");
			equals(helder.text.SystemFonts.get().match(f.family)?.family, f.family);
		}));
	});
	// (what a reload does with the new value: the old object kept, its contents the new)
	describe("swapped in place", () -> {
		test("an image: its size and pixels, a new version", async(() -> {
			var img = Asset.image("asset/files/pixels.png").load(), v = img.version;
			var other = new Image(3, 1, Bytes.alloc(12));
			img.replace(other);
			equals([img.width, img.height, img.pixels.length], [3, 1, 12]);
			assert(img.version > v);
		}));
		test("a font: the new face, a new id, ui's texts laid out again", async(() -> {
			var f = Asset.font("text/var.ttf").load();
			var id = f.id, g = helder.text.FontFile.generation, glyph = f.glyph("A".code);
			f.replace(helder.text.FontFile.parse(f.data));
			assert(f.id != id && helder.text.FontFile.generation == g + 1);
			equals(f.glyph("A".code), glyph);
		}));
	});
	describe("in ui's markup", () -> {
		test("<Loading> over an image: its fallback, then the image bound to the handle", async(() -> {
			// (a file no other test loads: not ready when it is rendered)
			var handle = Asset.image("asset/files/shown.png");
			var ui = new helder.ui.Ui(null, 200, 200);
			var dispose = helder.view.Render.render(UiFixture.view(handle), ui.root);
			ui.update();
			assert(!handle.ready && ui.root.find("wait") != null && ui.root.find("pic") == null, "the fallback first");
			var img = handle.load();
			ui.update();
			var node:Null<helder.ui.ImageNode> = cast ui.root.find("pic");
			assert(node != null && ui.root.find("wait") == null, "the image once loaded");
			equals(node.image, img);
			dispose();
		}));
	});
	describe("the handle", () -> {
		test("read before it is here: pending (a computation reading it waits); peek null", () -> {
			var a = new Asset<Int>("later");
			equals(a.peek(), null);
			var got:Array<Int> = [];
			var dispose = root(d -> {
				effect(() -> a.read(), v -> got.push(v));
				d;
			});
			flush();
			equals(got, []);
			a.resolve(4);
			flush();
			equals(got, [4]);
			dispose();
		});
		test("load suspends until it is resolved", async(() -> {
			var a = new Asset<Int>("later");
			var t = Async.launch(_ -> a.load());
			Async.yield();
			assert(!a.ready);
			a.resolve(4);
			equals(t.await(), 4);
		}));
		test("a reload in flight: Graph.isPending, the last value kept", () -> {
			var a = new Asset<String>("text");
			var pending:Array<Bool> = [];
			var dispose = root(d -> {
				renderEffect(() -> isPending(() -> a.read()), v -> pending.push(v));
				d;
			});
			flush();
			equals(isPending(() -> a.read()), false);
			a.resolve("one");
			flush();
			a.refresh(true);
			flush();
			equals(untrack(a.read), "one");
			a.resolve("two");
			flush();
			equals(untrack(a.read), "two");
			equals(pending, [false, true, false]);
			dispose();
		});
		test("its readers run again on a reload, the object the same", () -> {
			var a = new Asset<Array<Int>>("list"), seen = [], v = [1];
			a.resolve(v);
			var dispose = root(d -> {
				effect(() -> a.read(), x -> seen.push(x.length));
				d;
			});
			flush();
			a.refresh(true);
			flush();
			v.push(2);
			a.resolve(v);
			flush();
			dispose();
			a.refresh(true);
			a.resolve(v);
			flush();
			equals(seen, [1, 2]);
		});
	});
}

// (named, never called: its file is not bundled)
function unused():Asset<Bytes>
	return Asset.bytes("asset/files/dropped.txt");

// (Loading's fallback, then an image whose src is the asset's handle)
private class UiFixture implements helder.view.Markup {
	public static function view(handle:Asset<Image>)
		return <view>
			<helder.view.Flow.Loading fallback={<view tag="wait"/>}>
				<image tag="pic" src={handle}/>
			</helder.view.Flow.Loading>
		</view>;
}
