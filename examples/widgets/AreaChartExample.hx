// title: AreaChart
// summary: Two series of visitors over six months stacked, each line filled down to the one under it, a dot on each at the month under the pointer
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class AreaChartExample implements Markup {
	public static function view():View
		return <AreaChart tag="visitors" label="Visitors" labels={["Jan", "Feb", "Mar", "Apr", "May", "Jun"]}
			stacked={true}
			series={[{name: "Desktop", values: [186, 305, 237, 73, 209, 214]}, {name: "Mobile", values: [80, 200, 120, 190, 130, 140]}]}/>;
}
