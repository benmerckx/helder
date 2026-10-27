// title: Sign-up card
// summary: shadcn/ui's look on ui's widgets: a card with an input, a checkbox, a switch, a badge and buttons, light and dark
// tags: ui, theme
// demo: canvas 420x360
import helder.theme.Shadcn;
import helder.ui.draw.UiWindow;
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

// A card of shadcn's components under Shadcn.sheet; the switch turns dark mode on
class Signup implements Markup {
	static function main() {
		var email = signal(""), terms = signal(false), dark = signal(false);
		var w = new UiWindow("Sign up", 420, 360);
		w.ui.theme = Shadcn.sheet;
		effect(() -> w.ui.dark = dark.value);
		Render.render(<view slot="body" grow={1} padding={24}>
			<Card>
				<CardHeader>
					<CardTitle text="Create an account"/>
					<CardDescription text="Enter your email below"/>
					<CardAction><Badge variant="secondary" label="Beta"/></CardAction>
				</CardHeader>
				<CardContent>
					<view row-gap={12}>
						<Input value={email} placeholder="m@example.com"/>
						<Checkbox checked={terms} label="Accept terms"/>
						<Switch checked={dark} label="Dark mode"/>
					</view>
				</CardContent>
				<CardFooter>
					<view direction="row" column-gap={8}>
						<Button variant="outline" label="Cancel"/>
						<Button label="Sign up" disabled={() -> !terms.value}/>
					</view>
				</CardFooter>
			</Card>
		</view>, w.root);
		UiWindow.run();
	}
}
