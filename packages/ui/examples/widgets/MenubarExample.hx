// title: Menubar
// summary: An application's menus in a bar, one with a submenu, the last chosen shown under it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class MenubarExample implements Markup {
	public static function view():View {
		var chosen = signal("Nothing chosen");
		return <view row-gap={12}>
			<Menubar tag="app" label="Application" menus={[
				{label: "File", items: [{label: "New", shortcut: "Mod+N", onSelect: () -> chosen.value = "New"}, {label: "Open…", onSelect: () -> chosen.value = "Open"}]},
				{label: "Edit", items: [{label: "Undo", onSelect: () -> chosen.value = "Undo"}, {label: "Redo", onSelect: () -> chosen.value = "Redo"}]},
				{label: "View", items: [{label: "Zoom", items: [{label: "In", onSelect: () -> chosen.value = "Zoom in"}, {label: "Out", onSelect: () -> chosen.value = "Zoom out"}]}]}
			]}/>
			<text>{() -> chosen.value}</text>
		</view>;
	}
}
