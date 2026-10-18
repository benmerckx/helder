// title: Empty
// summary: An empty state: an icon, a title, a description and what to do next
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class EmptyExample implements Markup {
	public static function view():View {
		var made = signal(0);
		return <view width={360}><Empty tag="projects">
			<EmptyHeader>
				<EmptyMedia variant="icon"><text>📁</text></EmptyMedia>
				<EmptyTitle text="No projects yet"/>
				<EmptyDescription text="You haven't made a project. Start with your first one."/>
			</EmptyHeader>
			<EmptyContent>
				<Button tag="create" label="Create a project" onClick={() -> made.value++}/>
				<text>{() -> made.value == 0 ? "" : "Made " + made.value}</text>
			</EmptyContent>
		</Empty></view>;
	}
}
