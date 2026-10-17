import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.web.*;

// The smallest island: a button counting its clicks, alone in its bundle
// (counter.js: what an island's JavaScript weighs), on the demo page too
class Counter implements Markup {
	static function View(props:{start:Int}):hxmc.view.View {
		var count = signal(props.start);
		return <button class="small" onClick={() -> count.value++}>Clicked {count} times</button>;
	}

	public static final Island = hxmc.web.Island.define("small", View, {script: "counter.js"});

	static function main() {
		#if js
		Islands.start([Island]);
		#end
	}
}
