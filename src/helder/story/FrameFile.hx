package helder.story;

#if !(hxmc.target == "wasm32-wasi")
import haxe.io.Bytes;
import hxmc.unsafe.*;

// A frame's pixels in shared memory: a file (under /dev/shm on Linux, the
// studio's) mapped by the preview host, which writes each frame into it,
// and by the studio, which copies it out into its own texture's upload
// (helder.story.NativeHost's frames where the GPU shares no texture:
// llvmpipe). On Windows, where the GPU always shares (DXGI), it is a plain
// file written and read.
class FrameFile {
	public final path:String;
	public final size:Int;
	var map = Ptr.nil();

	function new(path:String, size:Int) {
		this.path = path;
		this.size = size;
	}

	// (the host) a file of size bytes, mapped to write
	public static function create(path:String, size:Int):FrameFile {
		var f = new FrameFile(path, size);
		if (Mem.os() == 2) {
			sys.io.File.saveBytes(path, Bytes.alloc(size));
			return f;
		}
		var fd = Arena.scopedValue(a -> Posix.open(a.cstring(path), O_RDWR | (Mem.os() == 1 ? 0x200 : 0x40), 384));
		if (fd < 0) throw 'helder.story: cannot create $path';
		// (its size: a byte written at its end)
		Posix.lseek(fd, size - 1, 0);
		Arena.scoped(a -> {
			var z:Ptr<UInt8> = a.alloc(1);
			z[0] = 0;
			Posix.write(fd, z, 1);
		});
		f.map = Posix.mmap(Ptr.nil(), size, 3, MAP_SHARED, fd, 0);
		Posix.close(fd);
		if (f.mapped()) return f;
		throw 'helder.story: cannot map $path';
	}

	// (the studio) the host's file, mapped to read (null: gone)
	public static function open(path:String, size:Int):Null<FrameFile> {
		var f = new FrameFile(path, size);
		if (Mem.os() == 2) return sys.FileSystem.exists(path) ? f : null;
		var fd = Arena.scopedValue(a -> Posix.open(a.cstring(path), 0, 0));
		if (fd < 0) return null;
		f.map = Posix.mmap(Ptr.nil(), size, 1, MAP_SHARED, fd, 0);
		Posix.close(fd);
		return f.mapped() ? f : null;
	}

	inline function mapped():Bool
		return !map.isNull() && map.toI64().toInt() != -1;

	// n bytes of b into the file
	public function write(b:Bytes, n:Int) {
		if (Mem.os() == 2) {
			var o = sys.io.File.write(path, true);
			o.writeBytes(b, 0, n);
			o.close();
			return;
		}
		LibC.memcpy(map, BytesPtr.of(b, 0, n), n);
	}

	// n bytes of the file into b
	public function read(b:Bytes, n:Int) {
		if (Mem.os() == 2) {
			var i = sys.io.File.read(path, true);
			i.readFullBytes(b, 0, n);
			i.close();
			return;
		}
		BytesPtr.copyIn(b, 0, map, n);
	}

	public function close() {
		if (mapped()) Posix.munmap(map, size);
		map = Ptr.nil();
	}

	// (the host) unmapped and gone
	public function remove() {
		close();
		try sys.FileSystem.deleteFile(path) catch (_:Dynamic) {}
	}

	static inline var O_RDWR = 2;
	static inline var MAP_SHARED = 1;
}
#end
