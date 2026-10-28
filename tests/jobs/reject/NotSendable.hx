import helder.jobs.Jobs;

// helder.jobs' sendable check: a class instance in a job's input is
// rejected at compile time, with where it is (the jobs lane expects
// "helder.jobs: count's input cannot be sent: .items[]: Item is a class")
class Item {
	public var n = 0;

	public function new() {}
}

class NotSendable {
	static function count(p:{items:Array<Item>}):Int
		return p.items.length;

	static function main() {
		helder.async.Async.main(_ -> {
			Jobs.run(count, {items: [new Item()]});
		});
	}
}
