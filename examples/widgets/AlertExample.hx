// title: Alert
// summary: Alerts with a title and a description, default and destructive
import helder.ui.widgets.Widgets.*;
import helder.view.*;

class AlertExample implements Markup {
	public static function view():View {
		return <view row-gap={12} width={400}>
			<Alert tag="info">
				<AlertTitle text="Heads up"/>
				<AlertDescription text="You can add widgets to your app with markup."/>
			</Alert>
			<Alert tag="error" variant="destructive">
				<AlertTitle text="Payment failed"/>
				<AlertDescription text="Check your card's details and try again."/>
			</Alert>
		</view>;
	}
}
