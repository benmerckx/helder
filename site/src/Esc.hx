using StringTools;

// HTML escaping for the strings the generator writes as raw HTML (Markdown,
// highlighted code, the API reference)
class Esc {
	public static function html(s:String):String
		return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;");
}
