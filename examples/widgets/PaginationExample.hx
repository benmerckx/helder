// title: Pagination
// summary: Pages of results, the current one shown under them
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class PaginationExample implements Markup {
	public static function view():View {
		var page = signal(2);
		return <view row-gap={12}>
			<Pagination tag="pages" page={page} count={10} label="Results"/>
			<text>{() -> "Page " + page.value + " of 10"}</text>
		</view>;
	}
}
