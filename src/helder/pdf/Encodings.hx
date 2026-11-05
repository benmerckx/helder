package helder.pdf;

import helder.pdf.PdfValue;
import helder.pdf.Document;

// The standard simple-font encodings as glyph names by code (PDF 32000's
// annex D: StandardEncoding, WinAnsiEncoding; MacRomanEncoding as WinAnsi
// below 128 and its own above), and glyph names to Unicode (WinAnsi's
// names through cp1252, the others the Latin fonts use, uniXXXX, uXXXX)
class Encodings {
	static final ASCII = "space exclam quotedbl numbersign dollar percent ampersand quotesingle parenleft parenright asterisk plus comma hyphen period slash zero one two three four five six seven eight nine colon semicolon less equal greater question at A B C D E F G H I J K L M N O P Q R S T U V W X Y Z bracketleft backslash bracketright asciicircum underscore grave a b c d e f g h i j k l m n o p q r s t u v w x y z braceleft bar braceright asciitilde";
	static final WIN_HIGH = "bullet Euro bullet quotesinglbase florin quotedblbase ellipsis dagger daggerdbl circumflex perthousand Scaron guilsinglleft OE bullet Zcaron bullet bullet quoteleft quoteright quotedblleft quotedblright bullet endash emdash tilde trademark scaron guilsinglright oe bullet zcaron Ydieresis space exclamdown cent sterling currency yen brokenbar section dieresis copyright ordfeminine guillemotleft logicalnot hyphen registered macron degree plusminus twosuperior threesuperior acute mu paragraph periodcentered cedilla onesuperior ordmasculine guillemotright onequarter onehalf threequarters questiondown Agrave Aacute Acircumflex Atilde Adieresis Aring AE Ccedilla Egrave Eacute Ecircumflex Edieresis Igrave Iacute Icircumflex Idieresis Eth Ntilde Ograve Oacute Ocircumflex Otilde Odieresis multiply Oslash Ugrave Uacute Ucircumflex Udieresis Yacute Thorn germandbls agrave aacute acircumflex atilde adieresis aring ae ccedilla egrave eacute ecircumflex edieresis igrave iacute icircumflex idieresis eth ntilde ograve oacute ocircumflex otilde odieresis divide oslash ugrave uacute ucircumflex udieresis yacute thorn ydieresis";
	static final CP1252 = [0x2022, 0x20AC, 0x2022, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x2022, 0x017D, 0x2022, 0x2022,
		0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x2022, 0x017E, 0x0178];
	static final STD_HIGH = [161 => "exclamdown cent sterling fraction yen florin section currency quotesingle quotedblleft guillemotleft guilsinglleft guilsinglright fi fl",
		177 => "endash dagger daggerdbl periodcentered", 182 => "paragraph bullet quotesinglbase quotedblbase quotedblright guillemotright ellipsis perthousand",
		191 => "questiondown", 193 => "grave acute circumflex tilde macron breve dotaccent dieresis", 202 => "ring cedilla", 205 => "hungarumlaut ogonek caron",
		208 => "emdash", 225 => "AE", 227 => "ordfeminine", 232 => "Lslash Oslash OE ordmasculine", 241 => "ae", 245 => "dotlessi",
		248 => "lslash oslash oe germandbls"];
	static final MAC_HIGH = "Adieresis Aring Ccedilla Eacute Ntilde Odieresis Udieresis aacute agrave acircumflex adieresis atilde aring ccedilla eacute egrave ecircumflex edieresis iacute igrave icircumflex idieresis ntilde oacute ograve ocircumflex odieresis otilde uacute ugrave ucircumflex udieresis dagger degree cent sterling section bullet paragraph germandbls registered copyright trademark acute dieresis notequal AE Oslash infinity plusminus lessequal greaterequal yen mu partialdiff summation product pi integral ordfeminine ordmasculine Omega ae oslash questiondown exclamdown logicalnot radical florin approxequal Delta guillemotleft guillemotright ellipsis space Agrave Atilde Otilde OE oe endash emdash quotedblleft quotedblright quoteleft quoteright divide lozenge ydieresis Ydieresis fraction currency guilsinglleft guilsinglright fi fl daggerdbl periodcentered quotesinglbase quotedblbase perthousand Acircumflex Ecircumflex Aacute Edieresis Egrave Iacute Icircumflex Idieresis Igrave Oacute Ocircumflex apple Ograve Uacute Ucircumflex Ugrave dotlessi circumflex tilde macron breve dotaccent ring cedilla hungarumlaut ogonek caron";
	static final EXTRA = ["fraction" => 0x2044, "fi" => 0xFB01, "fl" => 0xFB02, "ff" => 0xFB00, "ffi" => 0xFB03, "ffl" => 0xFB04, "breve" => 0x02D8,
		"dotaccent" => 0x02D9, "ring" => 0x02DA, "hungarumlaut" => 0x02DD, "ogonek" => 0x02DB, "caron" => 0x02C7, "Lslash" => 0x0141, "lslash" => 0x0142,
		"dotlessi" => 0x0131, "minus" => 0x2212, "notequal" => 0x2260, "infinity" => 0x221E, "lessequal" => 0x2264, "greaterequal" => 0x2265,
		"partialdiff" => 0x2202, "summation" => 0x2211, "product" => 0x220F, "pi" => 0x03C0, "integral" => 0x222B, "Omega" => 0x03A9,
		"radical" => 0x221A, "approxequal" => 0x2248, "Delta" => 0x2206, "lozenge" => 0x25CA, "nbspace" => 0x00A0, "sfthyphen" => 0x00AD];

	static var standard:Array<Null<String>>;
	static var win:Array<Null<String>>;
	static var mac:Array<Null<String>>;
	static var unicodes:Map<String, Int>;

	static function init() {
		if (win != null) return;
		var ascii = ASCII.split(" ");
		win = [for (_ in 0...256) null];
		standard = [for (_ in 0...256) null];
		mac = [for (_ in 0...256) null];
		for (i in 0...ascii.length) {
			win[32 + i] = ascii[i];
			standard[32 + i] = ascii[i];
			mac[32 + i] = ascii[i];
		}
		standard[39] = "quoteright";
		standard[96] = "quoteleft";
		var high = WIN_HIGH.split(" ");
		for (i in 0...high.length)
			win[127 + i] = high[i];
		for (start => names in STD_HIGH) {
			var n = names.split(" ");
			for (i in 0...n.length)
				standard[start + i] = n[i];
		}
		var m = MAC_HIGH.split(" ");
		for (i in 0...m.length)
			mac[128 + i] = m[i];
		unicodes = new Map();
		for (c in 32...256) {
			var n = win[c];
			if (n == null || unicodes.exists(n)) continue;
			unicodes.set(n, c >= 128 && c < 160 ? CP1252[c - 127] : c == 127 ? 0x2022 : c);
		}
		unicodes.set("quoteright", 0x2019);
		unicodes.set("quoteleft", 0x2018);
		unicodes.set("quotesingle", 0x27);
		unicodes.set("grave", 0x60);
		for (k => v in EXTRA)
			unicodes.set(k, v);
	}

	// a base encoding's names (null: the font's own)
	public static function named(name:Null<String>):Null<Array<Null<String>>> {
		init();
		return switch name {
			case "WinAnsiEncoding": win;
			case "MacRomanEncoding": mac;
			case "StandardEncoding": standard;
			case _: null;
		}
	}

	public static function standardEncoding():Array<Null<String>> {
		init();
		return standard;
	}

	// a glyph name's character (-1: none known)
	public static function unicode(name:String):Int {
		init();
		var u = unicodes.get(name);
		if (u != null) return u;
		if (StringTools.startsWith(name, "uni") && name.length >= 7) {
			var v = Std.parseInt("0x" + name.substr(3, 4));
			if (v != null) return v;
		}
		if (StringTools.startsWith(name, "u") && name.length >= 5 && name.length <= 7) {
			var v = Std.parseInt("0x" + name.substr(1));
			if (v != null) return v;
		}
		// (a name with a suffix: a.sc, a_b)
		var dot = name.indexOf(".");
		if (dot > 0) return unicode(name.substr(0, dot));
		return -1;
	}
}
