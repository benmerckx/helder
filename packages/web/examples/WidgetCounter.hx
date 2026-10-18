import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.web.widgets.Widgets.*;

// ui's Counter on the DOM's widgets: a signal, markup bound to it, a
// button that changes it (packages/ui/examples/Counter.hx on a canvas);
// the page links the theme's CSS (make web-widgets: bin/web/widgets)
class WidgetCounter implements Markup {
	static function main() {
		var count = signal(0);
		Render.render(<div style="display:flex;flex-direction:column;align-items:center;gap:12px;padding:24px">
			<div style="font-size:32px">{count}</div>
			<Button label="+1" onClick={() -> count.value++}/>
		</div>, js.Browser.document.body);
	}
}
