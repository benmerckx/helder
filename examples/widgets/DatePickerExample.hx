// title: DatePicker
// summary: A due date chosen on a calendar the button opens
import helder.ui.widgets.Widgets.*;
import helder.ui.widgets.Days;
import helder.view.*;
import helder.view.Reactive.*;

class DatePickerExample implements Markup {
	public static function view():View {
		var due:Signal<Null<Day>> = signal(null);
		return <view row-gap={8} width={220}>
			<DatePicker tag="due" value={due} today={{year: 2026, month: 10, day: 17}} placeholder="Pick a due date" label="Due date"/>
			<text>{() -> due.value == null ? "No date yet" : "Due " + due.value.day + " " + Days.MONTHS[due.value.month - 1]}</text>
		</view>;
	}
}
