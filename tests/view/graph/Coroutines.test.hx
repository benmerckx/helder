package view.graph;

import helder.async.Async;
import helder.test.Test;
import helder.view.graph.Graph.*;

// A coroutine computation (DESIGN.md 2, Holds): a task started now, on helder.async's loop,
// which also flushes the writes when its task ends.
function tests() {
	test("reads before the first suspension are tracked; a superseded run is cancelled", async(() -> {
		var id = signal(1);
		var log = [];
		var user = memo(task(() -> {
			var i = id();
			log.push('start $i');
			Async.delay(0.02);
			log.push('end $i');
			'user$i';
		}));
		var shown = [];
		root(_ -> renderEffect(() -> user(), v -> shown.push(v)));
		Async.delay(0.05);
		equals(shown, ["user1"]);
		id(2);
		Async.delay(0.005);
		id(3);
		Async.delay(0.05);
		equals(shown, ["user1", "user3"]);
		equals(log, ["start 1", "end 1", "start 2", "start 3", "end 3"]);
	}));
}
