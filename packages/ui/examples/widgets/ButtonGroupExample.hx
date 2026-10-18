// title: ButtonGroup
// summary: Buttons joined in a row, one with a text and a separator, and a vertical group
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class ButtonGroupExample implements Markup {
	public static function view():View {
		var count = signal(0);
		return <view row-gap={12} width={360}>
			<ButtonGroup tag="mail" label="Mail">
				<Button label="Archive" variant="outline"/>
				<Button label="Report" variant="outline"/>
				<Button label="Snooze" variant="outline"/>
			</ButtonGroup>
			<ButtonGroup tag="count" label="Count">
				<Button tag="less" label="−" variant="outline" onClick={() -> count.value--}/>
				<ButtonGroupText>{() -> Std.string(count.value)}</ButtonGroupText>
				<ButtonGroupSeparator/>
				<Button tag="more" label="+" variant="outline" onClick={() -> count.value++}/>
			</ButtonGroup>
			<ButtonGroup tag="zoom" orientation="vertical" label="Zoom">
				<Button label="In" variant="outline" size="sm"/>
				<Button label="Out" variant="outline" size="sm"/>
			</ButtonGroup>
		</view>;
	}
}
