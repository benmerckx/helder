// title: Avatar
// summary: Avatars with no image, showing their fallback initials, named for assistive technology
import helder.ui.widgets.Widgets.*;
import helder.view.*;

class AvatarExample implements Markup {
	public static function view():View {
		return <view direction="row" column-gap={12} align-items="center">
			<Avatar tag="ada" fallback="AL" label="Ada Lovelace"/>
			<Avatar tag="alan" fallback="AT" label="Alan Turing"/>
			<Avatar tag="grace" fallback="GH" label="Grace Hopper"/>
			<text>3 people</text>
		</view>;
	}
}
