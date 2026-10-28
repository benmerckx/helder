import helder.typescript.ir.Builder;
import helder.typescript.ir.Verifier;
import helder.typescript.ir.TextIR;
import hxmc.ir.Ir;
import haxe.ds.Vector;

class IrTests {
	static var checks = 0;
	static function check(ok:Bool, message:String) {
		if (!ok) throw message;
		checks++;
	}

	static function rejects(run:() -> Void, code:String) {
		var rejected = false;
		try run() catch (e:Dynamic) {
			rejected = StringTools.startsWith(Std.string(e), code);
		}
		check(rejected, "expected diagnostic " + code);
	}

	static function sample():Program {
		var p = new Program();
		var f = Builder.func(p, "unit", TVoid);
		p.main = f;
		var b = new Builder(p, f);
		var l = b.local("answer", TF64);
		b.out = [SSet(l, EBin(FAdd, EF64(20), EF64(22))), SReturn(null)];
		b.finish();
		return p;
	}

	static function main() {
		var p = sample();
		Verifier.check(p);
		check(true, "valid IR");
		var text = TextIR.dump(p);
		TextIR.parse(p, text);
		Verifier.check(p);
		check(TextIR.dump(p) == text, "text round trip");
		var golden = "tests/typescript/golden/basic.ir.json";
		if (Sys.args()[0] == "--write-golden") sys.io.File.saveContent(golden, text);
		check(sys.io.File.getContent(golden) == text, "golden IR changed");
		rejects(() -> TextIR.parse(p, '{"format":"bad","functions":[]}'), "TSHXIR002:");
		rejects(() -> TextIR.parse(p, StringTools.replace(text, '"ret": {', '"ret": {"invalid": true,')), "TSHXIR002:");
		var q = sample();
		q.main.body = Vector.fromArrayCopy([SSet(new Local(99, "foreign", TF64), EF64(1))]);
		rejects(() -> Verifier.check(q), "TSHXIR003:");
		q = sample();
		q.main.body = Vector.fromArrayCopy([SSet(q.main.locals[0], EStr("wrong"))]);
		rejects(() -> Verifier.check(q), "TSHXIR003:");
		q = sample();
		q.main.body = Vector.fromArrayCopy([SBreak]);
		rejects(() -> Verifier.check(q), "TSHXIR003:");
		q = sample();
		q.main.ret = TF64;
		q.main.body = new Vector(0);
		rejects(() -> Verifier.check(q), "TSHXIR003:");
		q = sample();
		var callee = Builder.func(q, "callee", TF64);
		callee.args = [new Local(0, "x", TF64)];
		callee.body = Vector.fromArrayCopy([SReturn(ELocal(callee.args[0]))]);
		q.main.body = Vector.fromArrayCopy([SSet(q.main.locals[0], ECall(callee, new Vector(0)))]);
		rejects(() -> Verifier.check(q), "TSHXIR003:");
		q.main.body = Vector.fromArrayCopy([SSet(q.main.locals[0], EBin(FAdd, ECall(callee, Vector.fromArrayCopy([EF64(1)])), EF64(2)))]);
		rejects(() -> Verifier.check(q), "TSHXIR003:");
		q = sample();
		q.main.body = Vector.fromArrayCopy([SIf(EF64(1), new Vector(0), new Vector(0))]);
		rejects(() -> Verifier.check(q), "TSHXIR003:");
		Sys.println(checks + " IR verifier/text checks passed");
	}
}
