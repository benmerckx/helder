// title: PieChart
// summary: Visitors by browser as a pie and as a donut, a slice's name and value under the pointer
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class PieChartExample implements Markup {
	public static function view():View {
		var browsers = [
			{name: "Chrome", value: 275.0},
			{name: "Safari", value: 200.0},
			{name: "Firefox", value: 187.0},
			{name: "Edge", value: 173.0},
			{name: "Other", value: 90.0}
		];
		return <view direction="row" column-gap={24}>
			<PieChart tag="browsers" label="Visitors by browser" slices={browsers} size={160}/>
			<PieChart tag="donut" label="Visitors by browser" slices={browsers} size={160} inner={0.6}/>
		</view>;
	}
}
