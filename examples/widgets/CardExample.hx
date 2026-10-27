// title: Card
// summary: A card with each of its parts: a header with a title, a description and an action, its content and a footer
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class CardExample implements Markup {
	public static function view():View {
		var saved = signal(false);
		return <view width={360}><Card tag="card">
			<CardHeader>
				<CardTitle text="Notifications"/>
				<CardDescription text="What we send you, and when."/>
				<CardAction><Button label="Edit" variant="link" size="sm"/></CardAction>
			</CardHeader>
			<CardContent><text>{() -> saved.value ? "Saved: a daily digest." : "A daily digest, by email."}</text></CardContent>
			<CardFooter><Button tag="save" label="Save" size="sm" onClick={() -> saved.value = true}/></CardFooter>
		</Card></view>;
	}
}
