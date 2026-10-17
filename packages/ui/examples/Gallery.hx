import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.draw.UiWindow;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.widgets.Widgets.*;

// hxmc.ui's widgets side by side, bound to signals that other widgets show:
// buttons, a checkbox and a switch, radio buttons, a slider driving a
// progress bar, tabs, a text field. In a window:
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

	public function new() {}

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
			{section("FIELD", <view row-gap={6}>
				<Field tag="name" value={name} placeholder="Your name"/>
				<text tag="greeting" color="#52525b">{() -> name.value == "" ? "Type a name." : "Hello, " + name.value + "!"}</text>
			</view>)}
		</scroll>;
}
