// title: NumberField
// summary: A quantity from 0 to 10 and a price stepping by a quarter, their values shown beside them
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class NumberFieldExample implements Markup {
	public static function view():View {
		var quantity = signal(1.0), price = signal(2.5);
		return <view row-gap={12}>
			<view direction="row" column-gap={12} align-items="center">
				<NumberField tag="quantity" value={quantity} min={0} max={10} label="Quantity"/>
				<text>{() -> "Quantity: " + quantity.value}</text>
			</view>
			<view direction="row" column-gap={12} align-items="center">
				<NumberField tag="price" value={price} min={0} step={0.25} label="Price"/>
				<text>{() -> "Price: " + price.value}</text>
			</view>
		</view>;
	}
}
