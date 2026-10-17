// title: Sign-up card
// summary: shadcn/ui's look on ui's widgets: a card with an input, a checkbox, a switch, badges and buttons, light and dark
// tags: ui, theme
// demo: canvas 420x360
import hxmc.theme.Shadcn;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

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
					<CardTitle>Create an account</CardTitle>
					<CardDescription>Enter your email below</CardDescription>
					<CardAction><Badge variant="secondary">Beta</Badge></CardAction>
				</CardHeader>
				<CardContent>
					<view row-gap={12}>
						<Input value={email} placeholder="m@example.com"/>
						<view direction="row" column-gap={8} align-items="center"><Checkbox checked={terms}/><Label>Accept terms</Label></view>
						<view direction="row" column-gap={8} align-items="center"><Switch on={dark}/><Label>Dark mode</Label></view>
					</view>
				</CardContent>
				<CardFooter>
					<view direction="row" column-gap={8}>
						<Button variant="outline">Cancel</Button>
						<Button disabled={() -> !terms.value}>Sign up</Button>
					</view>
				</CardFooter>
			</Card>
		</view>, w.root);
		UiWindow.run();
	}
}
