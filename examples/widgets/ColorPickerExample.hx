// title: ColorPicker
// summary: A colour picker bound to a signal, its colour's hex shown
import helder.ui.Color;
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class ColorPickerExample implements Markup {
	public static function view():View {
		var colour = signal(Color.rgb(0x3B82F6));
		return <view direction="row" column-gap={16} align-items="start">
			<ColorPicker tag="accent" value={colour} size={180} label="Accent"/>
			<text>{() -> colour.value.toHex().substr(0, 7)}</text>
		</view>;
	}
}
