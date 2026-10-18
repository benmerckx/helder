// title: ScrollArea
// summary: Fifty tags in a scrolled area 200 pixels high
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class ScrollAreaExample implements Markup {
	public static function view():View
		return <ScrollArea tag="tags" width={200} height={200} label="Tags">
			<view padding={12} row-gap={8}>{[for (i in 0...50) <text>{"v1.2.0-beta." + (50 - i)}</text>]}</view>
		</ScrollArea>;
}
