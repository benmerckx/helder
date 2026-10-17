// title: Command
// summary: A command menu: a search field filtering groups of items, the one chosen shown beside it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class CommandExample implements Markup {
	public static function view():View {
		var chosen = signal("none");
		return <view direction="row" column-gap={16} align-items="start">
			<view width={260}><Command tag="commands" placeholder="Type a command or search" label="Commands" groups={[
				{heading: "Suggestions", items: [{label: "Calendar", onSelect: () -> chosen.value = "Calendar"}, {label: "Calculator", disabled: true}]},
				{heading: "Settings", items: [{label: "Profile", shortcut: "Mod+P", onSelect: () -> chosen.value = "Profile"},
					{label: "Settings", shortcut: "Mod+S", onSelect: () -> chosen.value = "Settings"}]}
			]}/></view>
			<text>{() -> "Chosen: " + chosen.value}</text>
		</view>;
	}
}
