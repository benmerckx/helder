// title: Collapsible
// summary: A trigger showing or hiding more content, open at first, its state shown under it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class CollapsibleExample implements Markup {
	public static function view():View {
		var open = signal(true);
		return <view row-gap={12} width={300}>
			<Collapsible tag="repos" label="3 starred repositories" open={open}>
				<view row-gap={4}>
					<text>hxmc/ui</text>
					<text>hxmc/view</text>
					<text>hxmc/theme</text>
				</view>
			</Collapsible>
			<text>{() -> open.value ? "open" : "closed"}</text>
		</view>;
	}
}
