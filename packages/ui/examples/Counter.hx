import hxmc.view.*;
import hxmc.ui.draw.UiWindow;
import hxmc.view.Reactive.*;
import hxmc.ui.widgets.Widgets.*;

// The README's example: a signal, markup bound to it, a button that changes it
class Counter implements Markup {
	static function main() {
		var count = signal(0);
		var w = new UiWindow("Counter", 320, 200);
		Render.render(<view grow={1} padding={24} row-gap={12} align-items="center" justify="center">
			<text font-size={32}>{count}</text>
			<Button label="+1" primary onClick={() -> count.value++}/>
		</view>, w.root);
		UiWindow.run();
	}
}
