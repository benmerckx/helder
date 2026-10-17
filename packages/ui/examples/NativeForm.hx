import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.native.*;
import hxmc.ui.native.Controls.*;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;

// The same markup and signals as the drawn widgets, on the platform's own
// controls (hxmc.ui.native: GTK 3 on Linux, the DOM in a browser), laid
// out by hxmc.ui's flexbox at the sizes the platform measures. In a window:
//
//   haxe -lib hxmc.ui -cp packages/ui/examples -main NativeForm --custom-target hxmc=form -D hxmc.libc=glibc
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

	public function view():Esx
		return <view grow={1} padding={16} row-gap={10} font-family="DejaVu Sans" font-size={14}>
			<text font-size={20} font-weight={700}>Native controls</text>
			<text tag="greeting">{() -> name.value == "" ? "Who are you?" : "Hello, " + name.value + "!"}</text>
			<Field tag="name" value={name} placeholder="Your name"/>
			<Checkbox tag="agree" checked={agree} label="I agree to the terms"/>
			<view direction="row" column-gap={10} align-items="center">
				<Slider tag="volume" value={volume} step={0.05} style={{width: 220}}/>
				<text tag="volume-shown">{() -> Math.round(volume.value * 100) + "%"}</text>
			</view>
			<Progress tag="progress" value={volume} style={{width: 220}}/>
			<view direction="row" column-gap={8}>
				<Button tag="submit" label="Submit" enabled={agree} onClick={() -> submitted.value++}/>
				<Button tag="count" label={() -> "Submitted " + submitted.value + " times"}/>
			</view>
			<text color="#52525b" font-size={12}>The text above wraps as the platform's labels wrap it, and the layout follows the sizes the platform reports for each control.</text>
		</view>;
}
