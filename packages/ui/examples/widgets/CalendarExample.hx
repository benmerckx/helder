// title: Calendar
// summary: A month's days, the chosen one shown beside them; another choosing a range, its first and last day
import hxmc.ui.widgets.Widgets.*;
import hxmc.ui.widgets.Days;
import hxmc.ui.widgets.Widgets.DayRange;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class CalendarExample implements Markup {
	public static function view():View {
		var today:Day = {year: 2026, month: 10, day: 17};
		var day:Signal<Null<Day>> = signal(today);
		var trip:Signal<DayRange> = signal({from: {year: 2026, month: 10, day: 20}, to: {year: 2026, month: 10, day: 24}});
		var shown = (d:Null<Day>) -> d == null ? "…" : d.day + " " + Days.MONTHS[d.month - 1];
		return <view row-gap={16}>
			<view direction="row" column-gap={16} align-items="start">
				<Calendar tag="calendar" value={day} today={today}/>
				<text>{() -> day.value == null ? "No day chosen" : shown(day.value)}</text>
			</view>
			<view direction="row" column-gap={16} align-items="start">
				<Calendar tag="range" range={trip} today={today}/>
				<text>{() -> shown(trip.value.from) + " to " + shown(trip.value.to)}</text>
			</view>
		</view>;
	}
}
