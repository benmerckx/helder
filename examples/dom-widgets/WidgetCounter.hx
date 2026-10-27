import helder.view.*;
import helder.view.Reactive.*;
import helder.ui.widgets.Widgets.*;

// ui's Counter on the DOM's widgets: a signal, markup bound to it, a
// button that changes it (examples/counter/Counter.hx on a canvas);
// ui's widgets imported, each the DOM's of the same name in the DOM's
// renderer (@:renderer); the page links the theme's CSS (make
// web-widgets: bin/web/widgets)
class WidgetCounter implements Markup {
	static function main() {
		var count = signal(0);
		Render.render(<div style="display:flex;flex-direction:column;align-items:center;gap:12px;padding:24px">
			<div style="font-size:32px">{count}</div>
			<Button label="+1" onClick={() -> count.value++}/>
		</div>, js.Browser.document.body);
	}
}
