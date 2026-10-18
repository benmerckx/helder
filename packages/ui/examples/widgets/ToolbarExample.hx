// title: Toolbar
// summary: Formatting toggles and a button, one Tab stop, Left and Right moving between them
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class ToolbarExample implements Markup {
	public static function view():View {
		var bold = signal(false), italic = signal(false);
		return <view row-gap={12}>
			<Toolbar tag="format" label="Formatting">
				<Toggle tag="bold" pressed={bold} label="Bold" variant="outline"/>
				<Toggle tag="italic" pressed={italic} label="Italic" variant="outline"/>
				<Button tag="clear" label="Clear" variant="ghost" onClick={() -> batch(() -> {
					bold.value = false;
					italic.value = false;
				})}/>
			</Toolbar>
			<text>{() -> (bold.value ? "Bold" : "Not bold") + ", " + (italic.value ? "italic" : "not italic")}</text>
		</view>;
	}
}
