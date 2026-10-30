package helder.asset;

import haxe.io.Bytes;
#if (target.name == "hxmc")
import hxmc.unsafe.*;
#end

// An asset's bytes where the build put them (Bundle), one way on every
// platform:
// - desktop: the executable's own data (a resource: read-only, paged in by
//   the system when first touched), copied out once, no file opened;
// - Android: the APK's assets/<key> (stored, so the system maps it:
//   AAssetManager, AAsset_getBuffer), copied out once;
// - iOS: the app bundle's assets/<key>, beside the executable;
// - the web: assets/<key> beside the page, fetched (read: in the
//   background; readNow: the files os's browser.mjs fetched before main);
// - dev builds (file: the file's full path, which the macro gives them
//   only): from disk, where it is edited; on Android, which has no access
//   to it, from helder dev over its dev connection ("asset <key>", as a
//   build's library is fetched); on the web from the dev server;
// - other targets (Eval): the file at its path.
// read is a coroutine, for the web; elsewhere it reads at once.
class Files {
	// the bytes, at once (a model needed before anything runs: Model.of; on
	// the web one of those fetched before main)
	public static function readNow(key:String, ?file:String):Bytes {
		#if (target.name != "hxmc")
		return sys.io.File.getBytes(file != null ? file : key);
		#else
		#if hxmc.dev
		if (file != null) return devBytes(key, file, true);
		#end
		#if (hxmc.target == "wasm32-wasi")
		return try sys.io.File.getBytes(AssetPath.bundled(key)) catch (_:Dynamic) throw 'helder.asset: $key not fetched before main (browser.mjs\'s assets option: <module>.assets.json)';
		#else
		return bundleBytes(key);
		#end
		#end
	}

	// the bytes (fetched on the web, key's handles told how far: Assets.progressed)
	@:coroutine public static function read(key:String, ?file:String):Bytes {
		#if (hxmc.target == "wasm32-wasi")
		var told = (loaded, total) -> Assets.progressed(key, loaded, total);
		#if hxmc.dev
		if (file != null) return helder.async.Fetch.bytes("/__hxmc/" + AssetPath.url(AssetPath.bundled(key)) + "?" + Std.int(haxe.Timer.stamp() * 1000), told);
		#end
		return helder.async.Fetch.bytes(AssetPath.url(AssetPath.bundled(key)), told);
		#else
		var b = readNow(key, file);
		Assets.progressed(key, b.length, b.length);
		return b;
		#end
	}

	#if (target.name == "hxmc")
	// the bytes in a buffer off the collected heap, for a GC-free job
	// (ImageJobs): natively copied straight from the executable's data or
	// the APK's map; the caller owns it
	@:coroutine public static function readBuffer(key:String, ?file:String):IoBuffer {
		#if (hxmc.target != "wasm32-wasi" && hxmc.target != "ios-arm64" && hxmc.target != "ios-sim-arm64")
		#if hxmc.dev
		if (file != null) return IoBuffer.ofBytes(devBytes(key, file, false));
		#end
		var b:Null<IoBuffer> = null;
		mapped(key, (p, n) -> {
			b = IoBuffer.alloc(n);
			copy(b, p, n);
		});
		Assets.progressed(key, b.length, b.length);
		return b;
		#else
		return IoBuffer.ofBytes(read(key, file));
		#end
	}

	@:hxmc.unsafe static inline function copy(b:IoBuffer, p:Ptr, n:Int)
		LibC.memcpy(b.ptr, p, (n : hxmc.I64));

	static function bundleBytes(key:String):Bytes {
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
		var dir = haxe.io.Path.directory(Sys.programPath());
		return try sys.io.File.getBytes(dir + "/" + AssetPath.bundled(key)) catch (e:Dynamic) throw 'helder.asset: $key not in the app ($dir)';
		#elseif (hxmc.target == "wasm32-wasi")
		return sys.io.File.getBytes(AssetPath.bundled(key));
		#else
		var out:Null<Bytes> = null;
		mapped(key, (p, n) -> {
			out = Bytes.alloc(n);
			BytesPtr.copyIn(out, 0, p, n);
		});
		return out;
		#end
	}

	#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
	// f with the APK's file mapped (AASSET_MODE_BUFFER: the stored entry
	// mapped in place), closed after
	static function mapped(key:String, f:(Ptr, Int) -> Void) {
		var a = helder.os.android.Activity.activity;
		var m = a.isNull() ? Ptr.nil() : Mem.getPtr(a, 64); // ANativeActivity.assetManager
		if (m.isNull()) throw 'helder.asset: $key: no activity (Android\'s assets come with it)';
		var asset = Arena.scopedValue(ar -> AssetManager.AAssetManager_open(m, ar.cstring(key), 3));
		if (asset.isNull()) throw 'helder.asset: $key not in the APK (assets/$key)';
		var n = AssetManager.AAsset_getLength(asset);
		var p = AssetManager.AAsset_getBuffer(asset);
		if (p.isNull()) {
			AssetManager.AAsset_close(asset);
			throw 'helder.asset: $key: not mapped';
		}
		f(p, n);
		AssetManager.AAsset_close(asset);
	}
	#elseif (hxmc.target != "wasm32-wasi" && hxmc.target != "ios-arm64" && hxmc.target != "ios-sim-arm64")
	// the resources' indexes by name, read once
	static var index:Null<Map<String, Int>> = null;

	// f with the resource's bytes where they are (the executable's
	// read-only data: hxmc's table, an offset from it and a length per
	// resource, hxmc.rt.Bytes), after their header (Bundle's: its name, up to
	// a byte 1)
	static function mapped(key:String, f:(Ptr, Int) -> Void) {
		if (index == null) {
			index = new Map();
			var names = hxmc.NativeResource.names();
			for (i in 0...names.length)
				index.set(names[i], i);
		}
		var i = index.get(Bundle.PREFIX + key);
		if (i == null) throw 'helder.asset: $key not in this build (is it named by code that is left after dead code elimination?)';
		var t = Mem.sym("hxmc_resources");
		var p = t.add(Mem.getI32(t, 8 * i)), n = Mem.getI32(t, 8 * i + 4), h = 0;
		while (h < n && Mem.getU8(p, h) != 1)
			h++;
		f(p.add(h + 1), n - h - 1);
	}
	#end

	#if hxmc.dev
	// a dev build's file: from disk; on Android from helder dev (the
	// connection Hot has, HXMC_DEV or the APK's hxmc.dev-server)
	static function devBytes(key:String, file:String, now:Bool):Bytes {
		#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		var at = Sys.getEnv("HXMC_DEV");
		if (at == null || at == "") at = haxe.macro.Compiler.getDefine("hxmc.dev-server");
		if (at == null || at.indexOf(":") < 0) return bundleBytes(key);
		var fd = hxmc.NativeNet.socket();
		if (fd < 0 || hxmc.NativeNet.connect(fd, new sys.net.Host(at.substr(0, at.lastIndexOf(":"))).ip, Std.parseInt(at.substr(at.lastIndexOf(":") + 1))) < 0)
			throw 'helder.asset: $key: no dev server at $at';
		hxmc.NativeNet.setBlocking(fd, true);
		var req = Bytes.ofString("asset " + key + "\n");
		hxmc.NativeNet.send(fd, req, 0, req.length);
		var out = new haxe.io.BytesBuffer(), buf = Bytes.alloc(1 << 16);
		while (true) {
			var k = hxmc.NativeNet.recv(fd, buf, 0, buf.length);
			if (k <= 0) break;
			out.addBytes(buf, 0, k);
		}
		hxmc.NativeNet.close(fd);
		// (the reply: "ok\n" then the bytes, or "missing\n")
		var b = out.getBytes();
		if (b.length < 3 || b.getString(0, 3) != "ok\n") throw 'helder.asset: $key: helder dev has no such file';
		return b.sub(3, b.length - 3);
		#elseif (hxmc.target == "wasm32-wasi")
		return sys.io.File.getBytes(AssetPath.bundled(key));
		#else
		return try sys.io.File.getBytes(file) catch (e:Dynamic) throw 'helder.asset: $file: $e';
		#end
	}
	#end
	#end
}

#if (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
// libandroid's assets (asset_manager.h): reads may wait on the APK's pages,
// so no fast calls
@:hxmc.c @:hxmc.lib("libandroid.so") extern class AssetManager {
	static function AAssetManager_open(mgr:hxmc.unsafe.Ptr, name:hxmc.unsafe.Ptr, mode:Int):hxmc.unsafe.Ptr;
	static function AAsset_getLength(asset:hxmc.unsafe.Ptr):Int;
	static function AAsset_getBuffer(asset:hxmc.unsafe.Ptr):hxmc.unsafe.Ptr;
	static function AAsset_close(asset:hxmc.unsafe.Ptr):Void;
}
#end
