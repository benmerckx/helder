// expect: a field holding a scoped value
import hxmc.scoped.*;

@:build(hxmc.scoped.Scoped.build())
class WriterField {
	static var keep:hxmc.scoped.Grow.GrowWriter<Int>;

	@:scoped static function main() {
		keep = Scope.grow(Int).writer();
	}
}
