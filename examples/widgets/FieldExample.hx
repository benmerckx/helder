// title: Field
// summary: A field set of fields: a labelled input with a description, one shown invalid with its error, and a switch beside its label
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class FieldExample implements Markup {
	public static function view():View {
		var name = signal(""), email = signal("not an email"), news = signal(true);
		var error = () -> email.value.indexOf("@") < 0 ? "Enter an email address." : null;
		return <view width={360}><FieldSet tag="profile">
			<FieldLegend text="Profile"/>
			<FieldDescription text="How others see you."/>
			<FieldGroup>
				<Field tag="name">
					<FieldLabel text="Name"/>
					<Input value={name} placeholder="Ada Lovelace" label="Name"/>
					<FieldDescription text="Shown on your posts."/>
				</Field>
				<Field tag="email" invalid={() -> error() != null}>
					<FieldLabel text="Email"/>
					<Input value={email} label="Email" invalid={() -> error() != null}/>
					<FieldError text={error}/>
				</Field>
				<FieldSeparator/>
				<Field tag="news" orientation="horizontal">
					<FieldContent>
						<FieldLabel text="Newsletter"/>
						<FieldDescription text="A monthly email."/>
					</FieldContent>
					<Switch checked={news} label="Newsletter"/>
				</Field>
			</FieldGroup>
		</FieldSet></view>;
	}
}
