// title: Textarea
// summary: A text area four lines high, its length shown under it
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class TextareaExample implements Markup {
	public static function view():View {
		var message = signal("");
		return <view row-gap={8} width={320}>
			<Textarea tag="message" value={message} rows={4} placeholder="Type your message here." label="Message"/>
			<text>{() -> message.value.length + " characters"}</text>
		</view>;
	}
}
