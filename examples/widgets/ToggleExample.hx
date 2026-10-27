// title: Toggle
// summary: Toggles pressed or not, in both variants and three sizes, one disabled
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class ToggleExample implements Markup {
	public static function view():View {
		var bold = signal(true), italic = signal(false);
		return <view row-gap={12}>
			<view direction="row" column-gap={8} align-items="center">
				<Toggle tag="bold" pressed={bold} label="Bold"/>
				<Toggle tag="italic" pressed={italic} label="Italic" variant="outline"/>
				<text>{() -> (bold.value ? "bold" : "regular") + ", " + (italic.value ? "italic" : "upright")}</text>
			</view>
			<view direction="row" column-gap={8} align-items="center">
				<Toggle pressed={signal(false)} label="Small" size="sm"/>
				<Toggle pressed={signal(false)} label="Large" size="lg" variant="outline"/>
				<Toggle pressed={signal(true)} label="Disabled" disabled={true}/>
			</view>
		</view>;
	}
}
