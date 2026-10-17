// title: Button
// summary: A button's variants and sizes, one disabled, and one counting its clicks
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class ButtonExample implements Markup {
	public static function view():View {
		var clicks = signal(0);
		return <view row-gap={12}>
			<view direction="row" column-gap={8} align-items="center">
				<Button tag="counter" label="Click me" onClick={() -> clicks.value++}/>
				<text>{() -> clicks.value + " clicks"}</text>
			</view>
			<view direction="row" column-gap={8} wrap row-gap={8}>
				<Button label="Secondary" variant="secondary"/>
				<Button label="Outline" variant="outline"/>
				<Button label="Ghost" variant="ghost"/>
				<Button label="Destructive" variant="destructive"/>
				<Button label="Link" variant="link"/>
			</view>
			<view direction="row" column-gap={8} align-items="center">
				<Button label="Small" size="sm"/>
				<Button label="Large" size="lg"/>
				<Button label="Disabled" disabled={true}/>
			</view>
		</view>;
	}
}
