// title: Tooltip
// summary: Buttons whose tooltips show once the pointer rests on them, or the focus comes in
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;

class TooltipExample implements Markup {
	public static function view():View {
		return <view direction="row" column-gap={12} align-items="center" padding-top={40}>
			<Tooltip tag="save-tip" text="Saves the document">
				<Button tag="save" label="Save" variant="outline"/>
			</Tooltip>
			<Tooltip tag="share-tip" text="Shown below, at once" placement="below" delay={0}>
				<Button tag="share" label="Share" variant="outline"/>
			</Tooltip>
		</view>;
	}
}
