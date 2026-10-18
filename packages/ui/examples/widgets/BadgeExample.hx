// title: Badge
// summary: Badges in each variant
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;

class BadgeExample implements Markup {
	public static function view():View {
		return <view direction="row" column-gap={8} wrap row-gap={8}>
			<Badge tag="new" label="New"/>
			<Badge label="Secondary" variant="secondary"/>
			<Badge label="Destructive" variant="destructive"/>
			<Badge label="Outline" variant="outline"/>
			<Badge label="Ghost" variant="ghost"/>
			<Badge label="Link" variant="link"/>
		</view>;
	}
}
