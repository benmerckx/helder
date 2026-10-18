// title: LineChart
// summary: Two series of visitors over six months as lines, a dot on each at the month under the pointer
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class LineChartExample implements Markup {
	public static function view():View
		return <LineChart tag="visitors" label="Visitors" labels={["Jan", "Feb", "Mar", "Apr", "May", "Jun"]}
			series={[{name: "Desktop", values: [186, 305, 237, 73, 209, 214]}, {name: "Mobile", values: [80, 200, 120, 190, 130, 140]}]}/>;
}
