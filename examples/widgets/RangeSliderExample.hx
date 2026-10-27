// title: RangeSlider
// summary: A range slider of prices in steps of five, its two ends shown
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class RangeSliderExample implements Markup {
	public static function view():View {
		var low = signal(20.0), high = signal(75.0);
		return <view direction="row" column-gap={12} align-items="center">
			<RangeSlider tag="price" low={low} high={high} min={0} max={100} step={5} width={240} label="Price"/>
			<text>{() -> low.value + " – " + high.value}</text>
		</view>;
	}
}
