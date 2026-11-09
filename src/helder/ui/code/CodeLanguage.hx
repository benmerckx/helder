package helder.ui.code;

import helder.syntax.Lexer;
import helder.syntax.Scanner.Lang;

// What highlights a language's lines in a code editor (CodeModel): a line
// read from the state at its start, its tokens appended to out (start, end,
// class: helder.syntax.TokenClass, relative to the line, in order) and the
// next line's state returned. States are Ints that are equal when what is
// open at a line's start is the same: the editor reads again only from an
// edited line until a line's state is the one it had. Languages are
// registered by file extension (CodeLanguages); TypeScript, TSX and Haxe
// are helder.syntax's Lexer.
interface CodeLanguage {
	// its name ("tsx", "haxe")
	function name():String;
	function startState():Int;
	function tokenize(line:String, state:Int, out:Array<Int>):Int;
	// what starts a line comment ("//"; null: none)
	function lineComment():Null<String>;
}

// helder.syntax's Lexer as a CodeLanguage (TypeScript, TSX, Haxe, design files)
class SyntaxLanguage implements CodeLanguage {
	final lexer:Lexer;
	final named:String;

	public function new(lang:Lang) {
		lexer = new Lexer(lang);
		named = switch lang {
			case Ts: "typescript";
			case Tsx: "tsx";
			case Haxe: "haxe";
			case Markup: "helder";
		}
	}

	public function name():String
		return named;

	public function startState():Int
		return lexer.start();

	public function tokenize(line:String, state:Int, out:Array<Int>):Int
		return lexer.line(line, state, out);

	public function lineComment():Null<String>
		return "//";
}

// The languages by file extension: TypeScript (.ts, .mts, .cts, .js),
// TSX (.tsx, .jsx), Haxe (.hx) and design files (.helder) built in;
// register adds more
class CodeLanguages {
	static final factories:Map<String, Void->CodeLanguage> = [
		"ts" => () -> new SyntaxLanguage(Ts),
		"mts" => () -> new SyntaxLanguage(Ts),
		"cts" => () -> new SyntaxLanguage(Ts),
		"js" => () -> new SyntaxLanguage(Ts),
		"mjs" => () -> new SyntaxLanguage(Ts),
		"tsx" => () -> new SyntaxLanguage(Tsx),
		"jsx" => () -> new SyntaxLanguage(Tsx),
		"hx" => () -> new SyntaxLanguage(Haxe),
		"helder" => () -> new SyntaxLanguage(Markup)
	];

	// a language for files ending in .ext (made fresh for each editor: a language may keep state)
	public static function register(ext:String, make:Void->CodeLanguage)
		factories.set(ext.toLowerCase(), make);

	// the language of a path by its extension (null: none, plain text)
	public static function forPath(path:String):Null<CodeLanguage> {
		var dot = path.lastIndexOf(".");
		if (dot < 0) return null;
		var make = factories.get(path.substr(dot + 1).toLowerCase());
		return make == null ? null : make();
	}
}
