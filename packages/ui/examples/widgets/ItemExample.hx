// title: Item
// summary: A group of items, each with media, a title, a description and actions, an outlined one and a small one that clicks
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class ItemExample implements Markup {
	public static function view():View {
		var opened = signal(0);
		return <view width={380}><ItemGroup tag="people" label="People">
			<Item tag="ada" variant="outline">
				<ItemMedia variant="icon"><text>A</text></ItemMedia>
				<ItemContent>
					<ItemTitle text="Ada Lovelace"/>
					<ItemDescription text="Wrote the first program."/>
				</ItemContent>
				<ItemActions><Button label="Invite" variant="outline" size="sm"/></ItemActions>
			</Item>
			<ItemSeparator/>
			<Item tag="grace" size="sm" onClick={() -> opened.value++}>
				<ItemContent>
					<ItemTitle text="Grace Hopper"/>
					<ItemDescription text={"Opened " + "on click"}/>
				</ItemContent>
				<ItemFooter><text>{() -> "Opened " + opened.value + " times"}</text></ItemFooter>
			</Item>
		</ItemGroup></view>;
	}
}
