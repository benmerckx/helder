// title: Counter island
// summary: The smallest JavaScript island: a button counting its clicks, rendered into the page at build time, hydrated by its own 42 KB bundle
// tags: web, view, island, javascript
// demo: island
import helder.view.*;
import helder.view.graph.Graph.*;
import helder.web.*;

// The smallest island: a button counting its clicks, alone in its bundle
// (counter.js: what an island's JavaScript weighs), on the demo page too
class Counter implements Markup {
	static function View(props:{start:Int}):helder.view.View {
		var count = signal(props.start);
		return <button class="small" onClick={() -> count(c -> c + 1)}>Clicked {count} times</button>;
	}

	public static final Island = helder.web.Island.define("small", View, {script: "counter.js"});

	static function main() {
		#if js
		Islands.start([Island]);
		#end
	}
}
