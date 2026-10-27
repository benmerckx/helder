package app;

class Greeting {
	public static function text():String
		return haxe.macro.Compiler.getDefine("greeting") + " from the project";
}
