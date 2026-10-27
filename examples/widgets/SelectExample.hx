// title: Select
// summary: A fruit chosen from a list the button opens
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class SelectExample implements Markup {
	public static function view():View {
		var fruit = signal("pear");
		return <view direction="row" column-gap={12} align-items="center">
			<Select tag="fruit" value={fruit} options={["apple", "pear", "plum", "quince"]} labels={["Apple", "Pear", "Plum", "Quince"]} label="Fruit"
				width={140}/>
			<text>{() -> "Chosen: " + fruit.value}</text>
		</view>;
	}
}
