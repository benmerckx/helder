// title: Pagination
// summary: Pages of results, the current one shown under them
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class PaginationExample implements Markup {
	public static function view():View {
		var page = signal(2);
		return <view row-gap={12}>
			<Pagination tag="pages" page={page} count={10} label="Results"/>
			<text>{() -> "Page " + page.value + " of 10"}</text>
		</view>;
	}
}
