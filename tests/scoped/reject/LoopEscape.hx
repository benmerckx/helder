// expect: a value made in a loop iteration kept in a variable from outside the loop
import helder.scoped.*;

@:build(helder.scoped.Scoped.build())
class LoopEscape {
	@:scoped static function main() {
		var keep = Scope.slice(Int, 1);
		for (i in 0...3)
			keep = Scope.slice(Int, 2);
		Sys.println(keep.length);
	}
}
