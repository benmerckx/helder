// title: Table
// summary: A table of planets sorted by a click on a column's title, the selected one shown under it
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

private typedef Planet = {name:String, moons:Int};

class TableExample implements Markup {
	public static function view():View {
		var planets:Array<Planet> = [
			{name: "Mercury", moons: 0}, {name: "Venus", moons: 0}, {name: "Earth", moons: 1}, {name: "Mars", moons: 2},
			{name: "Jupiter", moons: 95}, {name: "Saturn", moons: 146}, {name: "Uranus", moons: 28}, {name: "Neptune", moons: 16}
		];
		var selected:Signal<Null<Planet>> = signal(null);
		return <view row-gap={8} width={320}>
			<Table tag="planets" rows={planets} selected={selected} height={200} label="Planets" columns={[
				{title: "Planet", cell: (p:Planet) -> p.name, compare: (a:Planet, b:Planet) -> Reflect.compare(a.name, b.name)},
				{title: "Moons", width: "80px", numeric: true, cell: (p:Planet) -> "" + p.moons, compare: (a:Planet, b:Planet) -> a.moons - b.moons}
			]}/>
			<text>{() -> selected.value == null ? "No planet selected" : selected.value.name + " selected"}</text>
		</view>;
	}
}
