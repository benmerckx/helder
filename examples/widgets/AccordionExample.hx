// title: Accordion
// summary: Three sections, at most one open: the first at first, the open one's index shown under them
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class AccordionExample implements Markup {
	public static function view():View {
		var open = signal(0);
		return <view row-gap={12} width={360}>
			<Accordion tag="faq" open={open} sections={[
				{label: "Is it accessible?", render: () -> <text>Yes: it has the roles and states assistive technology reads.</text>},
				{label: "Is it styled?", render: () -> <text>By a theme's rules, else not at all.</text>},
				{label: "Is it animated?", render: () -> <text>Where a theme's transitions say.</text>}
			]}/>
			<text>{() -> open.value < 0 ? "none open" : "section " + (open.value + 1) + " open"}</text>
		</view>;
	}
}
