// title: Sheet
// summary: A sheet along the right edge, opened by a button, editing a name, with a footer that closes it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class SheetExample implements Markup {
	public static function view():View {
		var open = signal(true), name = signal("Ada Lovelace");
		return <view row-gap={12} align-items="start">
			<Button tag="open" label="Open sheet" variant="outline" onClick={() -> open.value = true}/>
			<text>{() -> "Name: " + name.value}</text>
			<Sheet tag="profile" open={open} title="Edit profile" description="Make changes to your profile here.">
				<Input tag="name" value={name} label="Name"/>
				<SheetFooter><Button tag="save" label="Save" onClick={() -> open.value = false}/></SheetFooter>
			</Sheet>
		</view>;
	}
}
