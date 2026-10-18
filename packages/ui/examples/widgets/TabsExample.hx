// title: Tabs
// summary: Tabs bound to a signal, each showing its own panel; the same as a line
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class TabsExample implements Markup {
	public static function view():View {
		var tab = signal(0), lined = signal(1);
		var panels = ["Your account's name and email.", "Change your password here.", "What we notify you of."];
		return <view width={360} row-gap={24}>
			<Tabs tag="tabs" labels={["Account", "Password", "Notifications"]} selected={tab} render={i -> <text>{panels[i]}</text>}/>
			<Tabs tag="lined" variant="line" labels={["Account", "Password", "Notifications"]} selected={lined} render={i -> <text>{panels[i]}</text>}/>
		</view>;
	}
}
