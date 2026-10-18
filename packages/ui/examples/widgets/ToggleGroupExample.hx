// title: ToggleGroup
// summary: An alignment chosen among joined toggles, and a smaller outline group
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class ToggleGroupExample implements Markup {
	public static function view():View {
		var align = signal("left"), size = signal("m");
		return <view row-gap={12}>
			<ToggleGroup tag="align" value={align} options={["left", "centre", "right"]} labels={["Left", "Centre", "Right"]} label="Alignment"/>
			<ToggleGroup tag="size" value={size} options={["s", "m", "l"]} labels={["S", "M", "L"]} variant="outline" size="sm" label="Size"/>
			<text>{() -> "Aligned " + align.value + ", size " + size.value}</text>
		</view>;
	}
}
