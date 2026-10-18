import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.web.widgets.Widgets.*;

// the theme's sign-up card (packages/theme/examples/Signup.hx on a canvas)
// on the DOM's widgets: an input, a checkbox, a switch turning dark mode
// on, a badge and buttons, under the theme's CSS
class WidgetForm implements Markup {
	static function main() {
		var email = signal(""), terms = signal(false), dark = signal(false);
		effect(() -> js.Browser.document.documentElement.classList.toggle("dark", dark.value));
		Render.render(<div style="padding:24px;max-width:420px">
			<Card>
				<CardHeader>
					<CardTitle text="Create an account"/>
					<CardDescription text="Enter your email below"/>
					<CardAction><Badge variant="secondary" label="Beta"/></CardAction>
				</CardHeader>
				<CardContent>
					<div style="display:flex;flex-direction:column;gap:12px">
						<Input value={email} placeholder="m@example.com" label="Email"/>
						<Checkbox checked={terms} label="Accept terms"/>
						<Switch checked={dark} label="Dark mode"/>
					</div>
				</CardContent>
				<CardFooter>
					<div style="display:flex;gap:8px">
						<Button variant="outline" label="Cancel"/>
						<Button label="Sign up" disabled={() -> !terms.value}/>
					</div>
				</CardFooter>
			</Card>
		</div>, js.Browser.document.body);
	}
}
