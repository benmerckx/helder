// title: InputOTP
// summary: A six-digit code in two groups of three, partly typed, the code shown once complete
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;
import hxmc.view.Reactive.*;

class InputOTPExample implements Markup {
	public static function view():View {
		var code = signal("12"), done = signal("");
		return <view row-gap={12} align-items="start">
			<InputOTP tag="code" value={code} length={6} groups={[3, 3]} onComplete={c -> done.value = c}/>
			<text>{() -> done.value != "" && code.value == done.value ? "Code " + done.value : code.value.length + " of 6 digits"}</text>
		</view>;
	}
}
