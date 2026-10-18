// title: DropdownMenu
// summary: A menu of actions, a checkbox item and a destructive one, the last chosen shown beside it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class DropdownMenuExample implements Markup {
	public static function view():View {
		var chosen = signal("Nothing chosen"), grid = signal(true);
		return <view direction="row" column-gap={12} align-items="center">
			<DropdownMenu tag="file" label="File" items={[
				{label: "New", shortcut: "Mod+N", onSelect: () -> chosen.value = "New"},
				{label: "Open…", onSelect: () -> chosen.value = "Open"},
				{label: "", separator: true},
				{label: "Show grid", checked: grid},
				{label: "Delete", variant: "destructive", onSelect: () -> chosen.value = "Delete"}
			]}/>
			<text>{() -> chosen.value + (grid.value ? ", grid shown" : "")}</text>
		</view>;
	}
}
