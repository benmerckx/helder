// expect: a field holding a scoped value
import helder.scoped.*;

@:build(helder.scoped.Scoped.build())
class WriterField {
	static var keep:helder.scoped.Grow.GrowWriter<Int>;

	@:scoped static function main() {
		keep = Scope.grow(Int).writer();
	}
}
