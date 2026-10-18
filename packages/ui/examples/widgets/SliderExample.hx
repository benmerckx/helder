// title: Slider
// summary: A slider bound to a signal, one in steps of ten, one disabled
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class SliderExample implements Markup {
	public static function view():View {
		var volume = signal(0.4), level = signal(30.0);
		return <view row-gap={16}>
			<view direction="row" column-gap={12} align-items="center">
				<Slider tag="volume" value={volume} width={240} label="Volume"/>
				<text>{() -> Math.round(volume.value * 100) + "%"}</text>
			</view>
			<view direction="row" column-gap={12} align-items="center">
				<Slider tag="level" value={level} min={0} max={100} step={10} width={240} label="Level"/>
				<text>{() -> "" + level.value}</text>
			</view>
			<Slider tag="locked" value={signal(0.7)} width={240} disabled={true} label="Disabled"/>
		</view>;
	}
}
