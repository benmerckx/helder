// title: Skeleton
// summary: Skeletons where an avatar and two lines of text are still coming
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;

class SkeletonExample implements Markup {
	public static function view():View {
		return <view direction="row" column-gap={12} align-items="center">
			<Skeleton tag="avatar" width={48} height={48}/>
			<view row-gap={8}>
				<Skeleton tag="line" width={220} height={14}/>
				<Skeleton width={160} height={14}/>
			</view>
		</view>;
	}
}
