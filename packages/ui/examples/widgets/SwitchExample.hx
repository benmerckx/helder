// title: Switch
// summary: Switches bound to signals, in both sizes, one disabled
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class SwitchExample implements Markup {
	public static function view():View {
		var wifi = signal(true), small = signal(false);
		return <view row-gap={12}>
			<view direction="row" column-gap={12} align-items="center">
				<Switch tag="wifi" checked={wifi} label="Wi-Fi"/>
				<text>{() -> wifi.value ? "on" : "off"}</text>
			</view>
			<Switch tag="small" checked={small} label="Small" size="sm"/>
			<Switch tag="locked" checked={signal(true)} label="Disabled" disabled={true}/>
		</view>;
	}
}
