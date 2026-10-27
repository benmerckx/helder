// title: Label
// summary: Labels for fields, one dimmed while disabled
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class LabelExample implements Markup {
	public static function view():View {
		var email = signal("");
		return <view row-gap={8} width={240}>
			<Label tag="email-label" text="Email"/>
			<Input tag="email" value={email} placeholder="you@example.com"/>
			<Label tag="locked" text="Disabled" disabled={true}/>
		</view>;
	}
}
