// title: Toaster
// summary: Where toasts show: one shown at first, until closed, and a button adding more with an action
import helder.ui.widgets.Widgets.*;
import helder.ui.widgets.Toasts;
import helder.view.*;

class ToasterExample implements Markup {
	public static function view():View {
		var count = 0;
		Toasts.show("Event created", {kind: "success", duration: 0});
		return <view align-items="start">
			<Button tag="notify" label="Show a toast" variant="outline" onClick={() -> Toasts.show("Deleted " + (++count) + " files", {action: "Undo"})}/>
			<Toaster tag="toaster"/>
		</view>;
	}
}
