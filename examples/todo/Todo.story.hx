import Todo.Item;
import helder.story.Story;

// The todo list's screens (`helder studio examples/todo`: a flow a name's
// part before its "/"): empty, with three items, filtered to the done
// ones, each at the window's size; and on a phone (a story's size without
// width and height). The studio runs each in a process of its own.
final empty = story({name: "Todo/Empty", width: 480, height: 560, render: () -> new Todo().view()});

final items = story({name: "Todo/Three items", width: 480, height: 560, render: () -> listed().view()});

final done = story({
	name: "Todo/Done",
	width: 480,
	height: 560,
	render: () -> {
		var t = listed();
		t.filter("done");
		t.view();
	}
});

final phone = story({name: "Phone/Three items", render: () -> listed().view()});

// (three items, the second done)
private function listed():Todo {
	var t = new Todo();
	var list = [for (s in ["Buy milk", "Walk the dog", "Call Ana"]) new Item(s)];
	list[1].done(true);
	t.todos(list);
	return t;
}
