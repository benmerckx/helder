package helder.ui.widgets;

// a day of the (proleptic Gregorian) calendar: year, month (1 to 12), day (1 to 31)
typedef Day = {year:Int, month:Int, day:Int};

// Days as numbers (days from 1970-01-01), for Calendar's arithmetic: no time
// zones, no clocks (Howard Hinnant's algorithms)
class Days {
	public static final MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
		"December"];
	public static final WEEKDAYS = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

	public static function of(d:Day):Int {
		var y = d.month <= 2 ? d.year - 1 : d.year;
		var era = Math.floor(y / 400), yoe = y - era * 400;
		var mp = (d.month + 9) % 12, doy = Std.int((153 * mp + 2) / 5) + d.day - 1;
		var doe = yoe * 365 + Std.int(yoe / 4) - Std.int(yoe / 100) + doy;
		return era * 146097 + doe - 719468;
	}

	public static function day(n:Int):Day {
		var z = n + 719468, era = Math.floor(z / 146097), doe = z - era * 146097;
		var yoe = Std.int((doe - Std.int(doe / 1460) + Std.int(doe / 36524) - Std.int(doe / 146096)) / 365);
		var doy = doe - (365 * yoe + Std.int(yoe / 4) - Std.int(yoe / 100)), mp = Std.int((5 * doy + 2) / 153);
		var d = doy - Std.int((153 * mp + 2) / 5) + 1, m = mp < 10 ? mp + 3 : mp - 9;
		return {year: yoe + era * 400 + (m <= 2 ? 1 : 0), month: m, day: d};
	}

	// 0 Sunday to 6 Saturday
	public static function weekday(n:Int):Int
		return ((n + 4) % 7 + 7) % 7;

	// the days in a month
	public static function length(year:Int, month:Int):Int
		return month == 2 ? (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28) : [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}
