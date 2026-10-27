// title: Listbox
// summary: Days chosen in a list, any number of them, shown beside it
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class ListboxExample implements Markup {
	public static function view():View {
		var days = signal(["Tue", "Thu"]);
		return <view direction="row" column-gap={16} align-items="start">
			<Listbox tag="days" selected={days} options={["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]} multiple label="Days" width={120} height={168}/>
			<text>{() -> days.value.length == 0 ? "No days" : days.value.join(", ")}</text>
		</view>;
	}
}
