import Model;

// What a font needs to set a language: the letters beyond a to z (their
// capitals too), for the languages written in Latin most often in Europe
// and the Americas. A letter counts when the font has it, drawn or made of
// others (é from e and the acute).
class Languages {
	static final NEEDS:Array<{name:String, letters:String}> = [
		{name: "English", letters: ""},
		{name: "Dutch", letters: "áéíóúëïöü"},
		{name: "German", letters: "äöüß"},
		{name: "French", letters: "àâæçéèêëîïôœùûüÿ"},
		{name: "Spanish", letters: "áéíñóúü¡¿"},
		{name: "Portuguese", letters: "áâãàçéêíóôõú"},
		{name: "Italian", letters: "àèéìíîòóùú"},
		{name: "Danish, Norwegian", letters: "æøå"},
		{name: "Swedish, Finnish", letters: "åäö"},
		{name: "Polish", letters: "ąćęłńóśźż"},
		{name: "Czech, Slovak", letters: "áčďéěíňóřšťúůýžäľĺôŕ"},
		{name: "Hungarian", letters: "áéíóöőúüű"},
		{name: "Romanian", letters: "ăâîșț"},
		{name: "Croatian, Slovenian", letters: "čćđšž"},
		{name: "Turkish", letters: "çğıöşü"},
		{name: "Lithuanian, Latvian", letters: "ąčęėįšųūžāēģīķļņ"}
	];

	// each language and the letters it needs that the face lacks
	public static function of(face:Face):Array<{name:String, missing:Array<String>}>
		return [for (l in NEEDS) {name: l.name, missing: [for (c in needs(l.letters)) if (Workshop.state(face, c) == "empty") c]}];

	static function needs(letters:String):Array<String> {
		var out = [for (c in "abcdefghijklmnopqrstuvwxyz".split("")) c];
		for (c in new haxe.iterators.StringIteratorUnicode(letters))
			out.push(String.fromCharCode(c));
		var caps = [];
		for (c in out) {
			// (ß and ı have no capital of one letter here; Turkish's İ is its own)
			if (c == "ß" || c == "ı" || c == "¡" || c == "¿") continue;
			var u = c.toUpperCase();
			if (u != c && out.indexOf(u) < 0 && caps.indexOf(u) < 0) caps.push(u);
		}
		if (letters.indexOf("ı") >= 0) caps.push("İ");
		return out.concat(caps);
	}
}
