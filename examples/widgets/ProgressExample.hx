// title: Progress
// summary: A bar of how much is done, moved by buttons, and one not knowing
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class ProgressExample implements Markup {
	public static function view():View {
		var done = signal(0.4);
		return <view row-gap={12} width={260}>
			<Progress tag="upload" value={done} label="Upload"/>
			<view direction="row" column-gap={8} align-items="center">
				<Button tag="less" label="-10%" size="sm" variant="outline" onClick={() -> done.value = Math.max(0, done.value - 0.1)}/>
				<Button tag="more" label="+10%" size="sm" variant="outline" onClick={() -> done.value = Math.min(1, done.value + 0.1)}/>
				<text>{() -> Math.round(done.value * 100) + "% done"}</text>
			</view>
			<Progress tag="loading" value={null} label="Loading"/>
		</view>;
	}
}
