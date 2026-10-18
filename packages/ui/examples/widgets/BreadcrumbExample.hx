// title: Breadcrumb
// summary: The path to a page, a step chosen going back to it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class BreadcrumbExample implements Markup {
	public static function view():View {
		var path = signal(["Home", "Projects", "hxmc", "Docs"]);
		return <view row-gap={12}>
			{() -> <Breadcrumb tag="crumbs" items={path.value} onSelect={i -> path.value = path.value.slice(0, i + 1)}/>}
			<Button tag="reset" label="Back to Docs" size="sm" variant="outline" onClick={() -> path.value = ["Home", "Projects", "hxmc", "Docs"]}/>
		</view>;
	}
}
