import helder.async.Async;
import helder.jobs.Jobs;

// job(f) in Haxe: work.ts prints the same.
typedef Text = {text:String, sep:String};
typedef Counted = {count:Int, long:Array<String>, last:Null<String>};

class Work {
	static final shortest = 3;

	static function upper(s:String):String
		return s.toUpperCase();

	static function words(t:Text):Counted {
		var ws = t.text.split(t.sep).filter(w -> w.length >= shortest);
		return {count: ws.length, long: ws.map(upper), last: ws.length > 0 ? ws[ws.length - 1] : null};
	}

	static function square(x:Float):Float
		return x * x;

	static function answer():Float
		return 42;

	static function main()
		Async.main(_ -> {
			var r = Jobs.job(words).run({text: "a fleet of ships at sea", sep: " "});
			Sys.println('${r.count} ${r.long.join(",")} ${r.last}');
			var none = Jobs.job(words).run({text: "a b", sep: " "});
			Sys.println('${none.count} ${none.last}');
			Sys.println('${Jobs.job(square).run(12)} ${Jobs.job(answer).run()}');
		});
}
