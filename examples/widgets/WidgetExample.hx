#if !macro
import helder.theme.Shadcn;
import helder.ui.draw.UiWindow;
import helder.view.*;
#end

// A widget's example (<Name>Example.hx: its view) in a window, under
// Shadcn.sheet, on a page's body, padded:
//   haxe -lib helder -lib helder -cp examples/widgets -main WidgetExample -D widget=Button --custom-target hxmc=button
class WidgetExample #if !macro implements Markup #end {
	#if !macro
	static function main() {
		var w = new UiWindow(name(), 480, 320);
		w.ui.theme = Shadcn.sheet;
		Render.render(<view slot="body" grow={1} padding={24} align-items="start">{view()}</view>, w.root);
		UiWindow.run();
	}
	#end

	// (the widget -D widget names, and its example's view)
	static macro function name():haxe.macro.Expr
		return macro $v{haxe.macro.Context.definedValue("widget") ?? "Button"};

	static macro function view():haxe.macro.Expr {
		var w = haxe.macro.Context.definedValue("widget") ?? "Button";
		return macro $i{w + "Example"}.view();
	}
}
