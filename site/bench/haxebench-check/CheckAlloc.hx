import haxe.io.Bytes;

// the computation of BMAllocCode, smaller, with its results printed
class CheckAlloc {
	static function main() {
		var count = 20000;
		for (size in [100, 1000, 101, 1001, 102]) {
			var data:Array<Bytes> = [];
			for (i in 0...count) {
				var bytes = Bytes.alloc(size);
				bytes.fill(0, size, i % 256);
				data.push(bytes);
			}
			var cmp = 0, sum = 0;
			for (i in 0...count) {
				var bytes = Bytes.alloc(size);
				bytes.fill(0, size, (i + 1) % 256);
				var c = bytes.compare(data[i]);
				cmp += c > 0 ? 1 : c < 0 ? -1 : 0;
				sum = (sum + data[i].get(size - 1) * 31 + data[i].get(i % size)) & 0xFFFFFF;
			}
			Sys.println('alloc $size: compare signs $cmp, byte sum $sum');
		}
	}
}
