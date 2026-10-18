// title: Input
// summary: A field submitted with Enter, a password, an invalid one and a disabled one
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class InputExample implements Markup {
	public static function view():View {
		var email = signal(""), sent = signal("");
		return <view row-gap={8} width={280}>
			<Input tag="email" value={email} placeholder="Email" onSubmit={s -> sent.value = s}/>
			<text>{() -> sent.value == "" ? "Press Enter to submit." : "Submitted " + sent.value}</text>
			<Input tag="password" value={signal("secret")} password={true} label="Password"/>
			<Input tag="invalid" value={signal("not an email")} invalid={true} label="Invalid"/>
			<Input tag="disabled" value={signal("")} placeholder="Disabled" disabled={true}/>
		</view>;
	}
}
