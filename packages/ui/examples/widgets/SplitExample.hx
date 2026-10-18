// title: Split
// summary: A sidebar and its content, the divider between them dragged or moved by the arrow keys
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class SplitExample implements Markup {
	public static function view():View {
		var size = signal(140.0);
		return <view width={420} height={200} row-gap={8}>
			<Split tag="panes" size={size} min={80} max={300} label="Sidebar"
				first={<view padding={8}><text>Sidebar</text></view>}
				second={<view padding={8}><text>Content</text></view>}/>
			<text>{() -> "The sidebar is " + size.value + " pixels wide"}</text>
		</view>;
	}
}
