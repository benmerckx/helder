// title: Drawer
// summary: A drawer from the bottom edge, opened by a button, setting a goal; a drag down closes it
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class DrawerExample implements Markup {
	public static function view():View {
		var open = signal(true), goal = signal(350.0);
		return <view row-gap={12} align-items="start">
			<Button tag="open" label="Set goal" variant="outline" onClick={() -> open.value = true}/>
			<text>{() -> "Goal: " + goal.value + " calories a day"}</text>
			<Drawer tag="goal" open={open} title="Move goal" description="Set your daily activity goal.">
				<NumberField tag="calories" value={goal} step={10} min={200} max={400} label="Calories"/>
				<DrawerFooter><Button tag="submit" label="Submit" onClick={() -> open.value = false}/></DrawerFooter>
			</Drawer>
		</view>;
	}
}
