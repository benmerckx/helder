// title: Text shaping
// summary: Fonts parsed, shaped and rasterized in Haxe: kerning, Arabic joining, right-to-left and mixed runs, combining marks; type to reshape
// tags: ui, text, bidi, shaping
// demo: canvas 480x440
import helder.ui.draw.UiWindow;
import helder.view.*;
import helder.view.Reactive.*;

// What helder.text does for ui's text, with no system text engine: each
// line is shaped (kerning pairs, Arabic letters joined by their position in
// the word), split into runs by the bidi algorithm and laid out right to
// left where it reads so, and drawn from glyphs our own rasterizer made.
// The field below reshapes what is typed into it. In a window:
//
//   haxe -lib helder -cp examples/shaping -main Shaping --custom-target hxmc=shaping -D hxmc.libc=glibc
class Shaping implements Markup {
	static function main() {
		var w = new UiWindow("Text shaping", 480, 440);
		Render.render(new Shaping().view(), w.root);
		UiWindow.run();
	}

	public final input = signal("Haxe كتب 2026 שלום, café");

	public function new() {}

	static function Sample(props:{label:String, text:String}):View
		return <view direction="row" column-gap={12} align-items="center">
			<text width={92} font-size={12} color="#71717a">{props.label}</text>
			<text font-size={20}>{props.text}</text>
		</view>;

	public function view():View
		return <view grow={1} padding={20} row-gap={10} background="#fafafa" font-family="DejaVu Sans" font-size={14} color="#18181b">
			<text font-size={22} font-weight={700}>Text in pure Haxe</text>
			<view row-gap={8} background="#ffffff" radius={8} border-width={1} border-color="#e4e4e7" padding={12}>
				<Sample label="Kerning" text="AVATAR Tower WAVE"/>
				<Sample label="Arabic" text="مرحبا بالعالم"/>
				<Sample label="Hebrew" text="שלום עולם"/>
				<Sample label="Mixed" text="hxmc يكتب WebAssembly"/>
				<Sample label="Marks" text={"n\u0303 a\u0308 o\u0323\u0302 e\u0301"}/>
				<Sample label="Scripts" text="Ελληνικά Кириллица"/>
			</view>
			<field value={input} placeholder="Type in any script" label="Text to shape" onInput={e -> input.value = e.text} padding="8 12" radius={6}
				border-width={1} border-color="#e4e4e7" background="#ffffff"/>
			<text font-size={26}>{input}</text>
		</view>;
}
