package helder.typescript.lower;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.lower.Definitions.Scope;

// helder/platform's `platform` (src/helder/platform/index.ts): the target a
// program is built for, as constants folded where the program is compiled,
// as Haxe's Mem.os() and Mem.target() are (hxmc.ir.Lower.targetConst):
// `platform.os`, `platform.target` and `platform.arm` are literals, and a
// condition of them (=== and !== of literals, !, && and ||) is one too, so
// an `if` or a `?:` on it lowers only the branch it takes: what only the
// other platforms' branches call is not reached, so not linked.
//
//   os:     linux, macos, windows, wasi, android, ios
//   target: hxmc's (linux-x86_64, macos-arm64, windows-x86_64, wasm32-wasi,
//           android-arm64, ios-arm64...)
class Platform {
	public final os:String;
	public final target:String;
	public final arm:Bool;

	// (hxmc's names of its targets by Mem.target()'s codes: the build's when -D hxmc.target is not given)
	static final names = ["linux-x86_64", "linux-arm64", "macos-x86_64", "macos-arm64", "windows-x86_64", "windows-arm64", "wasm32-wasi", "linux-x86_64", "linux-arm64",
		"android-x86_64", "android-arm64"];

	public function new(defined:String->Null<String>) {
		var code = hxmc.ir.Lower.targetCode;
		target = defined("hxmc.target") ?? (code >= 0 && code < names.length ? names[code] : "linux-x86_64");
		arm = hxmc.ir.Lower.targetArm >= 0 ? hxmc.ir.Lower.targetArm == 1 : target.indexOf("arm64") >= 0;
		os = target.indexOf("wasm") == 0 ? "wasi" : target.indexOf("android") == 0 ? "android" : target.indexOf("ios") == 0
			|| hxmc.ir.Lower.targetPlatform == 1 || hxmc.ir.Lower.targetPlatform == 2 ? "ios" : target.split("-")[0];
	}

	// whether n reads helder/platform's platform (an identifier imported from it)
	static function isPlatform(n:Node):Bool {
		if (n.kind != KindIdentifier) return false;
		var from = Scope.imported(n.file, n.text);
		return from != null && from.module == "helder/platform" && from.name == "platform";
	}

	// a field of platform: its value
	public function field(n:Node):Null<Dynamic> {
		if (n.kind != KindPropertyAccessExpression || !isPlatform(n.expression())) return null;
		return switch n.name().text {
			case "os": os;
			case "target": target;
			case "arm": arm;
			case _: null;
		}
	}

	// platform read as a value (not one of its fields)
	public static function bare(n:Node):Bool
		return isPlatform(n) && !(n.parent != null && n.parent.kind == KindPropertyAccessExpression && n.parent.expression() == n);

	// a condition of platform's fields as its value (a String or a Bool), null
	// when it is not one (it reads something else, or no field of platform)
	public function constant(n:Node):Null<Dynamic> {
		var reads = false;
		function value(n:Node):Null<Dynamic> {
			while (n.kind == KindParenthesizedExpression) n = n.expression();
			return switch n.kind {
				case KindPropertyAccessExpression:
					var v = field(n);
					if (v != null) reads = true;
					v;
				case KindStringLiteral | KindNoSubstitutionTemplateLiteral: n.text;
				case KindTrueKeyword: true;
				case KindFalseKeyword: false;
				case KindPrefixUnaryExpression if (n.unaryOperator() == KindExclamationToken):
					var v = value(n.operand());
					v == null ? null : !truthy(v);
				case KindBinaryExpression:
					var op = n.operatorToken().kind;
					if (op == KindAmpersandAmpersandToken || op == KindBarBarToken) {
						var a = value(n.left());
						if (a == null) return null;
						// (false && x, true || x: a, whatever x is)
						if (truthy(a) == (op == KindBarBarToken)) return a;
						return value(n.right());
					}
					if (op != KindEqualsEqualsEqualsToken && op != KindExclamationEqualsEqualsToken && op != KindEqualsEqualsToken && op != KindExclamationEqualsToken)
						return null;
					var a = value(n.left()), b = value(n.right());
					if (a == null || b == null) return null;
					var same = a == b;
					op == KindEqualsEqualsEqualsToken || op == KindEqualsEqualsToken ? same : !same;
				case _: null;
			}
		}
		var v = value(n);
		return reads ? v : null;
	}

	public static function truthy(v:Dynamic):Bool
		return Std.isOfType(v, Bool) ? v : Std.isOfType(v, String) ? (v : String) != "" : v != null;
}
