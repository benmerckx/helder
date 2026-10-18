// title: NavigationMenu
// summary: Two triggers with panels of links and a plain link, the panel opening under the menu
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class NavigationMenuExample implements Markup {
	public static function view():View {
		var went = signal("");
		function link(label:String, text:String):View
			return <view role="link" focusable padding={8} row-gap={2} onClick={_ -> went.value = label}>
				<text font-weight={500}>{label}</text>
				<text>{text}</text>
			</view>;
		return <view width={420} row-gap={8}>
			<NavigationMenu tag="nav" items={[
				{label: "Getting started", render: () -> <view width={300}>{link("Introduction", "What it is and why.")}{link("Installation", "How to add it.")}</view>},
				{label: "Components", render: () -> <view width={300}>{link("Button", "Pressed to act.")}{link("Dialog", "A window over the page.")}</view>},
				{label: "Docs", onSelect: () -> went.value = "Docs"}
			]}/>
			<text>{() -> went.value == "" ? "Nothing followed yet." : "Followed " + went.value}</text>
		</view>;
	}
}
