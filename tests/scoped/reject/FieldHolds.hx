// expect: a field holding a scoped value
import helder.scoped.*;

class FieldHolds {
	static var kept:Slice<Int>;

	static function main()
		kept = Scope.slice(Int, 4);
}
