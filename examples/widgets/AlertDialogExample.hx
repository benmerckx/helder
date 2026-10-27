// title: AlertDialog
// summary: A destructive action confirmed in an alert dialog, which says whether it was cancelled
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class AlertDialogExample implements Markup {
	public static function view():View {
		var open = signal(true), status = signal("3 files");
		return <view row-gap={12} align-items="start">
			<Button tag="delete" label="Delete files" variant="destructive" onClick={() -> open.value = true}/>
			<text>{() -> status.value}</text>
			<AlertDialog tag="confirm" open={open} title="Delete 3 files?" description="This cannot be undone." action="Delete" variant="destructive"
				onAction={() -> status.value = "Deleted"} onCancel={() -> status.value = "Kept"}/>
		</view>;
	}
}
