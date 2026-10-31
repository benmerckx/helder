package helder.os.audio;

import haxe.io.Bytes;

// A sound file decoded whole, by its first bytes: a RIFF WAVE file (Wav)
// or an Ogg Vorbis one (Vorbis.decode); interleaved samples at the file's
// rate, mono(Sfx.RATE) for Sfx's effects:
//
//   var laser = sfx.add(Sound.decode(Asset.sound("audio/laser.ogg").load()).mono(Sfx.RATE));
//
// Music is not decoded whole: Sfx.music streams its Ogg Vorbis bytes.
class Sound {
	public static function decode(b:Bytes):Wav {
		if (b.length >= 4 && b.getString(0, 4) == "OggS") return Vorbis.decode(b);
		return Wav.decode(b);
	}
}
