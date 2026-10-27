// title: HoverCard
// summary: A link that shows a card about its user once the pointer rests on it
import helder.ui.widgets.Widgets.*;
import helder.view.*;

class HoverCardExample implements Markup {
	public static function view():View {
		return <view direction="row" column-gap={6} align-items="center">
			<text>Made by</text>
			<HoverCard tag="user" content={<view direction="row" column-gap={12} width={260}>
				<Avatar fallback="HX"/>
				<view row-gap={4}>
					<text>@hxmc</text>
					<text>A UI library compiled with its own compiler.</text>
				</view>
			</view>}>
				<Button tag="link" label="@hxmc" variant="link"/>
			</HoverCard>
		</view>;
	}
}
