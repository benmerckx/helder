// title: Calendar
// summary: A month's days, the chosen one shown beside them
import hxmc.ui.widgets.Widgets.*;
import hxmc.ui.widgets.Days;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class CalendarExample implements Markup {
	public static function view():View {
		var today:Day = {year: 2026, month: 10, day: 17};
		var day:Signal<Null<Day>> = signal(today);
		return <view direction="row" column-gap={16} align-items="start">
			<Calendar tag="calendar" value={day} today={today}/>
			<text>{() -> day.value == null ? "No day chosen" : day.value.day + " " + Days.MONTHS[day.value.month - 1]}</text>
		</view>;
	}
}
