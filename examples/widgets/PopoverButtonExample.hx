// title: PopoverButton
// summary: A button whose popover holds fields, open at first, its state shown beside it
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class PopoverButtonExample implements Markup {
	public static function view():View {
		var open = signal(true), width = signal("100%");
		return <view direction="row" column-gap={12} align-items="center">
			<PopoverButton tag="dimensions" label="Dimensions" open={open}>
				<view row-gap={8} width={220}>
					<text>Set the dimensions for the layer.</text>
					<Input tag="width" value={width} label="Width"/>
				</view>
			</PopoverButton>
			<text>{() -> (open.value ? "open" : "closed") + ", width " + width.value}</text>
		</view>;
	}
}
