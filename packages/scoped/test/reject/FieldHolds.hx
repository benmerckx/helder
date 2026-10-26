// expect: a field holding a scoped value
import hxmc.scoped.*;

class FieldHolds {
	static var kept:Slice<Int>;

	static function main()
		kept = Scope.slice(Int, 4);
}
