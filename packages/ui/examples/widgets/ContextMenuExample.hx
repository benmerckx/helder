// title: ContextMenu
// summary: A menu opened by a right click on an area, or by the menu key, the last chosen shown in it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class ContextMenuExample implements Markup {
	public static function view():View {
		var chosen = signal("Right click here");
		return <ContextMenu tag="area" label="Actions" items={[
			{label: "Copy", onSelect: () -> chosen.value = "Copied"},
			{label: "Paste", onSelect: () -> chosen.value = "Pasted"},
			{label: "", separator: true},
			{label: "Delete", variant: "destructive", onSelect: () -> chosen.value = "Deleted"}
		]}>
			<view tag="target" focusable width={240} height={100} radius={8} background="#80808022" align-items="center" justify="center">
				<text>{() -> chosen.value}</text>
			</view>
		</ContextMenu>;
	}
}
