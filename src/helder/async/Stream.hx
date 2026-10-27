package helder.async;

import haxe.io.Bytes;

// bytes that come in: read waits until there are some (at most len into b
// at pos), 0 at the end
interface Source {
	@:coroutine function read(b:Bytes, pos:Int, len:Int):Int;
}

// bytes that go out: write returns once all of them are written
interface Sink {
	@:coroutine function write(b:Bytes, pos:Int, len:Int):Void;
}
