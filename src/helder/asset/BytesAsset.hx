package helder.asset;

import haxe.io.Bytes;

// Asset.bytes's and Asset.sound's loader: the file's bytes (a sound's not
// decoded yet); a reload's bytes take the old ones' place (value's readers
// told), since a Bytes cannot change its length
class BytesAsset {
	public static function load(key:String, ?file:String):Asset<Bytes>
		return Assets.handle("bytes", key, _ -> Files.read(key, file), (_, fresh) -> fresh);

	public static function sound(key:String, ?file:String):Asset<Bytes>
		return Assets.handle("sound", key, _ -> Files.read(key, file), (_, fresh) -> fresh);
}
