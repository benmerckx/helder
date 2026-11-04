package helder.pack.ios;

import haxe.io.Bytes;
import helder.pack.ios.Plist;
import helder.test.Test;

// The app icon's Assets.car (AssetCatalog) parsed back: the BOM's blocks,
// the header, the key format, one rendition a size with its pixels (BGRA,
// rows padded to 32 bytes), the MultiSized renditions, the facet and the
// bitmap keys; actool's name hash; the .icns
function tests() {
	// (a 2x2-pixel pattern scaled up: each icon's corners known)
	final icon = (px:Int) -> {
		var b = Bytes.alloc(px * px * 4);
		for (y in 0...px)
			for (x in 0...px) {
				var o = 4 * (y * px + x);
				b.set(o, x < px >> 1 ? 255 : 0);
				b.set(o + 1, y < px >> 1 ? 200 : 10);
				b.set(o + 2, px & 0xff);
				b.set(o + 3, 255);
			}
		b;
	};
	final car = AssetCatalog.read(AssetCatalog.appIcon(icon, "16.0"));

	test("actool's name hash", () -> {
		// (AppIcon's identifier in a catalog of Apple's actool, Img001's in viraptor/actool's goldens)
		equals(AssetCatalog.nameHash("AppIcon"), 6849);
		equals(AssetCatalog.nameHash("Img001"), 0x27d5);
	});
	test("the BOM's named blocks, the header, the key format, the metadata", () -> {
		equals(car.blocks, ["CARHEADER", "RENDITIONS", "FACETKEYS", "APPEARANCEKEYS", "KEYFORMAT", "EXTENDED_METADATA", "BITMAPKEYS"]);
		equals([car.coreui, car.keySemantics, car.count], [975, 2, 8]);
		equals(car.keyformat, [7, 13, 12, 15, 16, 9, 17, 1, 2]);
		equals(car.renditionKeySize, 18);
		equals([car.platform, car.deployment], ["ios", "16.0"]);
	});
	test("one rendition a size, idiom and scale, its pixels BGRA", () -> {
		var images = [for (r in car.renditions) if (r.layout == 12) r];
		equals([for (r in images) '${r.key.get(15)}:${r.key.get(9)}:${r.width}@${r.scale}'].join(" "),
			"6:8:1024@100 1:4:120@200 2:5:152@200 2:6:167@200 1:4:180@300");
		for (r in images) {
			equals(r.format, "BGRA");
			equals([r.compression, r.key.get(17), r.key.get(1), r.key.get(2)], [0, 6849, 85, 220]);
			var row = (r.width * 4 + 31) & ~31;
			equals(r.tlvs.get(0x3ef).getInt32(0), row);
			equals(r.pixels.length, row * r.height);
			var src = icon(r.width), last = 4 * (r.width * r.width - 1), d = (r.height - 1) * row + 4 * (r.width - 1);
			equals([r.pixels.get(0), r.pixels.get(1), r.pixels.get(2), r.pixels.get(3)], [src.get(2), src.get(1), src.get(0), 255]);
			equals([r.pixels.get(d), r.pixels.get(d + 1), r.pixels.get(d + 2)], [src.get(last + 2), src.get(last + 1), src.get(last)]);
		}
	});
	test("a MultiSized rendition an idiom: its sizes in points and indices", () -> {
		var multi = [for (r in car.renditions) if (r.layout == 1010) r];
		equals([for (r in multi) r.key.get(15)], [1, 2, 6]);
		var sizes = (r:AssetCatalog.Rendition) -> [for (i in 0...r.data.getInt32(8)) r.data.getInt32(12 + 12 * i) + "/" + r.data.getInt32(20 + 12 * i)];
		equals(multi[0].data.getString(0, 4), "SISM");
		equals([for (r in multi) sizes(r).join(",")], ["60/4", "76/5,83/6", "1024/8"]);
		equals([for (r in multi) r.key.get(2)], [218, 218, 218]);
	});
	test("the facet AppIcon, its bitmap keys", () -> {
		equals(car.facets.get("AppIcon").toHex(), "000000000300010055000200dc001100c11a");
		var masks = car.bitmapKeys.get(6849);
		equals(masks.getInt32(12), 9);
		// (scale: 1, 2 and 3; idiom 1, 2 and 6; size index 0, 4, 5, 6 and 8; identifier any)
		equals([masks.getInt32(16 + 4 * 2), masks.getInt32(16 + 4 * 3), masks.getInt32(16 + 4 * 5), masks.getInt32(16 + 4 * 6)],
			[0xe, 0x46, 0x171, -1]);
	});
	test("Info.plist's keys: CFBundleIcons and ~ipad's, the icon's name", () -> {
		var k = AssetCatalog.plistKeys();
		equals(k.get("CFBundleIcons"),
			PDict(["CFBundlePrimaryIcon" => PDict(["CFBundleIconFiles" => PArray([PString("AppIcon60x60")]), "CFBundleIconName" => PString("AppIcon")])]));
	});
	test(".icns: its entries' types and PNGs", () -> {
		var icns = helder.pack.apple.Icns.write(px -> helder.image.PngEncoder.encode(icon(px), px, px));
		equals(icns.getString(0, 4), "icns");
		equals((icns.get(4) << 24) | (icns.get(5) << 16) | (icns.get(6) << 8) | icns.get(7), icns.length);
		var types = [], at = 8;
		while (at < icns.length) {
			types.push(icns.getString(at, 4));
			var n = (icns.get(at + 4) << 24) | (icns.get(at + 5) << 16) | (icns.get(at + 6) << 8) | icns.get(at + 7);
			equals(icns.sub(at + 8, 4).toHex(), "89504e47");
			at += n;
		}
		equals(types, ["icp4", "icp5", "ic11", "ic12", "ic07", "ic13", "ic08", "ic14", "ic09", "ic10"]);
	});
}
