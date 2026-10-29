// title: Native controls
// summary: The same markup and signals as the drawn widgets, on the platform's own controls (GTK 3 on Linux, the DOM in a browser), laid out by helder.ui's flexbox
// tags: ui, view, native
import helder.ui.*;
import helder.ui.native.*;
import helder.ui.native.Controls.*;
import helder.view.*;
import helder.view.graph.Graph.*;

// The same markup and signals as the drawn widgets, on the platform's own
// controls (helder.ui.native: GTK 3 on Linux, the DOM in a browser), laid
// out by helder.ui's flexbox at the sizes the platform measures. In a window:
//
//   haxe -lib helder -cp examples -main NativeForm --custom-target hxmc=form -D hxmc.libc=glibc
//
// (NativeTest drives it under Xvfb, native-web.mjs in Chromium.)
class NativeForm implements Markup {
	static function main() {
		var host = new NativeHost("Native controls", 440, 380);
		Render.render(new NativeForm().view(), host.root);
		host.run();
	}

	public final name = signal("");
	public final agree = signal(false);
	public final volume = signal(0.3);
	public final submitted = signal(0);

	public function new() {}

	public function view():View
		return <view grow={1} padding={16} row-gap={10} font-family="DejaVu Sans" font-size={14}>
			<text font-size={20} font-weight={700}>Native controls</text>
			<text tag="greeting">{() -> name() == "" ? "Who are you?" : "Hello, " + name() + "!"}</text>
			<Field tag="name" value={name} placeholder="Your name"/>
			<Checkbox tag="agree" checked={agree} label="I agree to the terms"/>
			<view direction="row" column-gap={10} align-items="center">
				<Slider tag="volume" value={volume} step={0.05} style={{width: 220}}/>
				<text tag="volume-shown">{() -> Math.round(volume() * 100) + "%"}</text>
			</view>
			<Progress tag="progress" value={volume} style={{width: 220}}/>
			<view direction="row" column-gap={8}>
				<Button tag="submit" label="Submit" enabled={agree} onClick={() -> submitted(c -> c + 1)}/>
				<Button tag="count" label={() -> "Submitted " + submitted() + " times"}/>
			</view>
			<text color="#52525b" font-size={12}>The text above wraps as the platform's labels wrap it, and the layout follows the sizes the platform reports for each control.</text>
		</view>;
}
