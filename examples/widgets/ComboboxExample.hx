// title: Combobox
// summary: A field whose typing filters a list of cities, the one chosen shown under it
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class ComboboxExample implements Markup {
	public static function view():View {
		var city = signal(""), chosen = signal("none");
		return <view row-gap={12} align-items="start">
			<Combobox tag="city" value={city} options={["Amsterdam", "Antwerp", "Berlin", "Bern", "Brussels"]} placeholder="Choose a city" label="City"
				onChoose={c -> chosen.value = c}/>
			<text>{() -> "Chosen: " + chosen.value}</text>
		</view>;
	}
}
