package helder.asset;

#if macro
import haxe.macro.Expr;
import helder.definition.HaxeAdapter;
import helder.definition.Kernel;

// Asset.image(path), font, model, sound, bytes and embed as definitions
// (src/helder/compiler/DESIGN.md 4): the argument, a path literal relative
// to the asset root, read through the definitions' kernel (anything else is
// rejected as not static, at its position), and handled as AssetMacro has
// it: the file found and bundled, the typed handle returned.
class AssetDefinition implements Definition<HaxeAdapter, Expr> {
	public final name:String;

	final kind:String;

	public function new(kind:String) {
		this.kind = kind;
		name = "Asset." + kind;
	}

	public function generate(arg:KNode, a:HaxeAdapter):Expr {
		// (the check: AssetCheck's, TypeScript's the same)
		var path = new AssetCheck(kind).generate(arg, a);
		return switch kind {
			case "model": AssetMacro.model(path);
			case "embed": AssetMacro.embed(path);
			case k: AssetMacro.handle(path, k);
		}
	}

	// (the forwarders': Asset's @:definition macros)
	public static function forward(kind:String, path:Expr):Expr {
		var d = new AssetDefinition(kind);
		var a = new HaxeAdapter(d.name);
		return d.generate(a.node(path), a);
	}
}
#end
