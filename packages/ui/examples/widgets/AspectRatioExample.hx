// title: AspectRatio
// summary: A 16 by 9 box as wide as its column, its height following
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class AspectRatioExample implements Markup {
	public static function view():View
		return <view width={320}><AspectRatio tag="frame" ratio={16 / 9}>
			<view grow={1} align-items="center" justify="center" background="#e4e4e7" radius={8}><text>16 : 9</text></view>
		</AspectRatio></view>;
}
