import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.widgets.Widgets.*;

// hxmc.ui's widgets side by side, bound to signals that other widgets show:
// buttons, a checkbox and a switch, radio buttons, a slider driving a
// progress bar, tabs, a text field, images fitted three ways. In a window:
//
//   haxe -lib hxmc.ui -cp packages/ui/examples -main Gallery --custom-target hxmc=gallery -D hxmc.libc=glibc
//
// (GalleryTest drives it headless.)
class Gallery implements Markup {
	static function main() {
		var w = new UiWindow("Gallery", 560, 520);
		Render.render(new Gallery().view(), w.root);
		UiWindow.run();
	}

	public final clicks = signal(0);
	public final checked = signal(true);
	public final on = signal(false);
	public final size = signal("Medium");
	public final volume = signal(0.4);
	public final tab = signal(0);
	public final name = signal("");
	final picture = landscape(120, 60);

	public function new() {}

	// a landscape drawn pixel by pixel: sky, a sun, hills (an image without a file)
	public static function landscape(w:Int, h:Int):Image {
		var img = new Image(w, h);
		for (y in 0...h)
			for (x in 0...w) {
				var fx = x / w, fy = y / h;
				var r = 96 + 80 * fy, g = 165 + 60 * fy, b = 250 - 20 * fy;
				var dx = fx - 0.75, dy = fy - 0.3, sun = Math.sqrt(dx * dx * w * w + dy * dy * h * h) / (h * 0.16);
				if (sun < 1) {
					r = 253;
					g = 224 - 40 * sun;
					b = 71;
				}
				var hill = 0.62 + 0.1 * Math.sin(fx * 7.0), far = 0.55 + 0.08 * Math.sin(fx * 4.0 + 1.3);
				if (fy > far) {
					r = 74;
					g = 158 - 30 * (fy - far);
					b = 110;
				}
				if (fy > hill) {
					r = 34 + 20 * fy;
					g = 120 + 30 * fy;
					b = 60;
				}
				var o = 4 * (y * w + x);
				img.pixels.set(o, Std.int(r));
				img.pixels.set(o + 1, Std.int(g));
				img.pixels.set(o + 2, Std.int(b));
				img.pixels.set(o + 3, 255);
			}
		return img;
	}

	function section(title:String, content:Esx):Esx
		return <view row-gap={8}>
			<text font-size={12} font-weight={700} color="#71717a">{title}</text>
			{content}
		</view>;

	static final TABS = [
		"An overview of the widgets: each is a function of its props, bound to signals.",
		"Details: the content of a tab is rendered again when the selection changes.",
		"Notes: every widget here takes the keyboard focus and works with the keyboard."
	];

	function tabContent(i:Int):Esx
		return <view tag="tab-content" padding={12} radius={8} background="#ffffff" border-width={1} border-color="#e4e4e7">{TABS[i]}</view>;

	public function view():Esx
		return <scroll grow={1} padding={20} row-gap={18} background="#fafafa" font-family="DejaVu Sans" font-size={14} color="#18181b">
			<text font-size={22} font-weight={700}>Widgets</text>
			{section("BUTTONS", <view direction="row" column-gap={8} align-items="center">
				<Button tag="plain" label="Plain" onClick={() -> clicks.value++}/>
				<Button tag="primary" label="Primary" primary onClick={() -> clicks.value += 10}/>
				<text tag="clicks" color="#52525b">{() -> "clicked " + clicks.value}</text>
			</view>)}
			{section("TOGGLES", <view direction="row" column-gap={24} align-items="center">
				<Checkbox tag="check" checked={checked} label="Checkbox"/>
				<Switch tag="switch" on={on} label={"Switch"}/>
				<text tag="toggles" color="#52525b">{() -> (checked.value ? "checked" : "unchecked") + ", " + (on.value ? "on" : "off")}</text>
			</view>)}
			{section("RADIO", <view direction="row" column-gap={24}>
				<Radio tag="size" value={size} options={["Small", "Medium", "Large"]}/>
				<text tag="size-shown" color="#52525b">{() -> "size: " + size.value}</text>
			</view>)}
			{section("SLIDER AND PROGRESS", <view row-gap={10}>
				<view direction="row" column-gap={12} align-items="center">
					<Slider tag="volume" value={volume} step={0.05} width={200}/>
					<text tag="volume-shown" color="#52525b">{() -> Math.round(volume.value * 100) + "%"}</text>
				</view>
				<Progress value={volume} width={200}/>
			</view>)}
			{section("TABS", <Tabs tag="tab" labels={["Overview", "Details", "Notes"]} selected={tab} render={tabContent}/>)}
			{section("IMAGES: FILL, CONTAIN, COVER", <view direction="row" column-gap={12} align-items="start">
				<image tag="fill" src={picture} width={110} height={70} radius={8}/>
				<image tag="contain" src={picture} fit="contain" width={110} height={70} radius={8} background="#e4e4e7"/>
				<image tag="cover" src={picture} fit="cover" width={110} height={70} radius={8}/>
				<image tag="natural" src={picture} radius={30}/>
			</view>)}
			{section("FIELD", <view row-gap={6}>
				<Field tag="name" value={name} placeholder="Your name"/>
				<text tag="greeting" color="#52525b">{() -> name.value == "" ? "Type a name." : "Hello, " + name.value + "!"}</text>
			</view>)}
		</scroll>;
}
