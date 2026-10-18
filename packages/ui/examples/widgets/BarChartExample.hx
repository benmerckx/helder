// title: BarChart
// summary: Two series of visitors over six months, a bar each per month, the values shown under the pointer
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class BarChartExample implements Markup {
	public static function view():View
		return <BarChart tag="visitors" label="Visitors" labels={["Jan", "Feb", "Mar", "Apr", "May", "Jun"]}
			series={[{name: "Desktop", values: [186, 305, 237, 73, 209, 214]}, {name: "Mobile", values: [80, 200, 120, 190, 130, 140]}]}/>;
}
