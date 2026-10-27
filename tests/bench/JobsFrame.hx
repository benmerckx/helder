import haxe.io.Bytes;
import helder.text.*;
import helder.ui.*;
import helder.ui.draw.DrawText;

// The main thread's frame in tests/bench/Jobs.hx and JobsWasm.hx: a ui laid
// out in full (its width changed), and user code's garbage: small objects
// and arrays, a 50th of them kept in a ring of 20,000 (promoted, then
// dropped: the old space fills too). -D jobs_bare: the garbage alone.
class JobsFrame {
	#if !jobs_bare
	static var ui:Ui;
	#end
	static var wide = false;
	public static var check = 0.0;
	// (GARBAGE_KB: as allocated, about 190 KB a frame of 256)
	public static var garbageKb = 256;
	static final kept:Array<Dynamic> = [for (_ in 0...20000) null];
	static var keptAt = 0;
	static var serial = 0;

	public static function frame() {
		#if !jobs_bare
		wide = !wide;
		ui.resize(wide ? 1180 : 1200, 800);
		ui.update();
		check += ui.root.children[0].contentHeight;
		#end
		// (96 bytes an iteration, as written)
		for (_ in 0...Std.int(garbageKb * 1024 / 96)) {
			var o = {id: serial++, x: serial * 0.5, tags: [serial, serial + 1]};
			if (serial % 50 == 0) {
				kept[keptAt] = o;
				keptAt = (keptAt + 1) % kept.length;
			}
			check += o.tags.length;
		}
	}

	// (20 sections of 10 cards, Bench's: about 2,000 nodes, 400 texts)
	public static function setup(font:Bytes) {
		#if !jobs_bare
		var fonts = new SystemFonts();
		fonts.add(font);
		ui = new Ui(new DrawText(fonts), 1200, 800);
		ui.root.style.fontFamily = "DejaVu Sans";
		ui.root.style.fontSize = 13;
		var page = new Node("page");
		page.style.overflow = Scroll;
		page.style.grow = 1;
		page.style.minHeight = 0;
		page.style.padding = 12;
		page.style.rowGap = 12;
		ui.root.append(page);
		for (s in 0...20) {
			var section = new Node("section");
			section.style.direction = Row;
			section.style.wrap = true;
			section.style.columnGap = 8;
			section.style.rowGap = 8;
			page.append(section);
			for (c in 0...10) {
				var card = new Node("card");
				card.style.grow = 1;
				card.style.basis = 200;
				card.style.padding = 8;
				card.style.rowGap = 6;
				card.style.borderWidth = 1;
				section.append(card);
				card.append(new TextNode('Card ${s * 10 + c}'));
				var row = new Node("row");
				row.style.direction = Row;
				row.style.columnGap = 4;
				card.append(row);
				for (b in 0...6) {
					var box = new Node("box");
					box.style.grow = b % 3;
					box.style.width = 10 + b * 3;
					box.style.height = 12 + (b & 1) * 6;
					row.append(box);
				}
				card.append(new TextNode("The quick brown fox jumps over the lazy dog, then a wizard's job is to vex chumps quickly in fog.".substr(0, 40 + (c * 13) % 50)));
				var button = new Node("button");
				button.style.alignSelf = End;
				button.style.width = 60;
				button.style.height = 20;
				card.append(button);
			}
		}
		ui.update();
		#end
	}
}
