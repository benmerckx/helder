// title: Sortable
// summary: Tasks put in order by dragging them, or by Alt and the arrow keys
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class SortableExample implements Markup {
	public static function view():View {
		var tasks = signal(["Write the docs", "Fix the build", "Review the changes", "Release"]);
		return <view row-gap={12} width={260}>
			<Sortable tag="tasks" items={tasks} render={(t:String) -> <text>{t}</text>} label="Tasks"/>
			<text>{() -> "First: " + tasks.value[0]}</text>
		</view>;
	}
}
