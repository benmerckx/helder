// title: Checkbox
// summary: Checkboxes bound to signals: one checked, one mixed, one disabled
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class CheckboxExample implements Markup {
	public static function view():View {
		var terms = signal(true), all = signal(false), mixed = signal(true);
		return <view row-gap={12}>
			<view direction="row" column-gap={12} align-items="center">
				<Checkbox tag="terms" checked={terms} label="Accept the terms"/>
				<text>{() -> terms.value ? "accepted" : "not accepted"}</text>
			</view>
			<view direction="row" column-gap={12} align-items="center">
				<Checkbox tag="all" checked={all} mixed={mixed} label="Select all"/>
				<text>{() -> mixed.value ? "some" : all.value ? "all" : "none"}</text>
			</view>
			<Checkbox tag="locked" checked={signal(true)} label="Disabled" disabled={true}/>
		</view>;
	}
}
