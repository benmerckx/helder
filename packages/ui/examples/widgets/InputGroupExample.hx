// title: InputGroup
// summary: An input with addons before and after it: a prefix and a suffix, and a button that clears it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class InputGroupExample implements Markup {
	public static function view():View {
		var site = signal("example"), query = signal("");
		return <view row-gap={12} width={320}>
			<InputGroup tag="site">
				<InputGroupAddon><InputGroupText text="https://"/></InputGroupAddon>
				<InputGroupInput value={site} label="Site"/>
				<InputGroupAddon align="inline-end"><InputGroupText text=".com"/></InputGroupAddon>
			</InputGroup>
			<InputGroup tag="search">
				<InputGroupInput value={query} placeholder="Search" label="Search"/>
				<InputGroupAddon align="inline-end"><Button tag="clear" label="Clear" variant="ghost" size="sm" onClick={() -> query.value = ""}/></InputGroupAddon>
			</InputGroup>
		</view>;
	}
}
