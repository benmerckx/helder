// title: RadioGroup
// summary: A radio group bound to a signal, with labels, and one disabled
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class RadioGroupExample implements Markup {
	public static function view():View {
		var plan = signal("pro");
		return <view direction="row" column-gap={32} align-items="start">
			<view row-gap={12}>
				<RadioGroup tag="plan" value={plan} options={["free", "pro", "team"]} labels={["Free", "Pro", "Team"]} label="Plan"/>
				<text>{() -> "plan: " + plan.value}</text>
			</view>
			<RadioGroup tag="locked" value={signal("on")} options={["on", "off"]} labels={["On", "Off"]} disabled={true} label="Disabled"/>
		</view>;
	}
}
