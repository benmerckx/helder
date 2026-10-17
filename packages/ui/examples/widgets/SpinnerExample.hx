// title: Spinner
// summary: A spinner turning beside a loading message
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;

class SpinnerExample implements Markup {
	public static function view():View {
		return <view direction="row" column-gap={8} align-items="center">
			<Spinner tag="loading" label="Loading files"/>
			<text>Loading files…</text>
		</view>;
	}
}
