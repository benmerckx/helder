// title: NativeSelect
// summary: A select whose options are the platform's own menu where it has one (macOS, Windows), else drawn
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class NativeSelectExample implements Markup {
	public static function view():View {
		var status = signal("todo");
		return <view row-gap={8}>
			<NativeSelect tag="status" value={status} options={["todo", "doing", "done"]} labels={["To do", "In progress", "Done"]} label="Status"/>
			<text>{() -> "Status: " + status.value}</text>
		</view>;
	}
}
