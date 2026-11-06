package helder.text;

// A spellchecker (helder.text.Spell: the platform's).
interface SpellChecker {
	// the language's tag ("en_US")
	var language(default, null):String;
	// whether word is spelled right
	function check(word:String):Bool;
	// the corrections offered for word, the likeliest first
	function suggest(word:String):Array<String>;
	// word added to the user's dictionary (correct from now on)
	function add(word:String):Void;
}
