package studio;

import helder.ui.*;
import helder.ui.gesture.Gesture;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import studio.Theme.c;

using StringTools;

// The inspector, while a screen is zoomed into: the selected node's layout
// (width, height, padding, gap), style (background, colour, radius) and
// text, each read from its element in the source (helder.syntax) and
// written back there (Studio.setAttribute: an attribute set or added, the
// file's formatting kept, one history). A live literal's change shows in
// the screens' next frame (patched, then saved); another builds. A number's
// label scrubs it: dragged left or right, a point per two.
class Inspector implements Markup {
	public static function view(studio:Studio):View {
		return <view tag="inspector" slot="floating" position="absolute" right={12} top={12} width={Theme.INSPECTOR} padding="8 12"
			onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<Show when={studio.selection() != null} fallback={<text color={c("fg3")} font-size={Theme.SMALL} padding="4 0">Click a part of the screen to select it.</text>}>
				{field(studio, "width", "Width", true)}
				{field(studio, "height", "Height", true)}
				{field(studio, "padding", "Padding", true)}
				{field(studio, gapName(studio), "Gap", true)}
				{field(studio, "background", "Fill", false)}
				{field(studio, "radius", "Radius", true)}
				{field(studio, "color", "Color", false)}
				<Show when={hasText(studio)}>
					<view slot="field">
						<text slot="field-label" cursor="default">Text</text>
						<field tag="field-text" slot="field-input" label="Text" value={textValue(studio)} onInput={e -> studio.setText(e.text)}
							onBlur={() -> studio.endGesture()}/>
					</view>
				</Show>
				<view slot="field">
					<text slot="field-label" cursor="default">Source</text>
					<text tag="inspector-source" padding="3 7" color={c("fg2")}>{source(studio)}</text>
				</view>
			</Show>
		</view>;
	}

	// one attribute's row: its label (a number's scrubs it), its value as written
	static function field(studio:Studio, name:String, label:String, number:Bool):View {
		var start = 0.0;
		return <view tag={"field-" + name} slot="field">
			<text tag={"scrub-" + name} slot="field-label" onPan={g -> {
				switch g.state {
					case Began:
						start = Std.parseFloat(value(studio, name));
						if (Math.isNaN(start)) start = 0;
					case Changed:
						studio.setAttribute(name, Std.string(Math.round(start + g.tx / 2)), 'scrub:$name');
					case _:
						studio.endGesture();
				}
			}}>{label}</text>
			<field tag={"input-" + name} slot="field-input" label={label} value={value(studio, name)} placeholder={placeholder(studio, name)}
				onInput={e -> if (valid(name, e.text, number)) studio.setAttribute(name, e.text)}
				onKeyDown={e -> if (e.key == Key.ENTER) studio.endGesture()} onBlur={() -> studio.endGesture()}/>
		</view>;
	}

	// (a value worth writing: a number for a number's field, a colour for a colour's)
	static function valid(name:String, text:String, number:Bool):Bool {
		var t = text.trim();
		if (t == "") return true;
		if (name == "padding" || name == "gap") return ~/^-?[0-9.]+( +-?[0-9.]+){0,3}$/.match(t);
		if (number) return ~/^-?[0-9]+(\.[0-9]+)?(%|px)?$/.match(t) || t == "auto" || t == "fill";
		// (#rgb is a prefix of #rrggbb while it is typed: written at six or eight digits)
		if (name == "background" || name == "color") return ~/^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.match(t) || ~/^(rgb|hsl|oklch)a?\(.*\)$/.match(t);
		return true;
	}

	// the attribute's value as written (its quotes or braces left out)
	static function value(studio:Studio, name:String):String {
		var el = studio.element();
		var a = el == null ? null : el.attr(name);
		if (a == null) return "";
		var lit = a.literal();
		var t = lit != null ? lit.text(el.doc.text) : a.valueText();
		if (t == null) return "";
		return t.length >= 2 && (t.charAt(0) == '"' || t.charAt(0) == "'") ? t.substring(1, t.length - 1) : t;
	}

	static function placeholder(studio:Studio, name:String):String {
		var s = studio.selection();
		if (s == null) return "";
		return switch name {
			case "width": Std.string(Math.round(s.width));
			case "height": Std.string(Math.round(s.height));
			case _: "–";
		}
	}

	// the gap's attribute: the one written (gap, row-gap, column-gap), else gap
	static function gapName(studio:Studio):String {
		var el = studio.element();
		if (el == null) return "gap";
		for (n in ["gap", "row-gap", "column-gap", "rowGap", "columnGap"])
			if (el.attr(n) != null) return n;
		return "gap";
	}

	static function hasText(studio:Studio):Bool {
		var el = studio.element();
		return el != null && Studio.textRun(el) != null;
	}

	static function textValue(studio:Studio):String {
		var el = studio.element();
		var r = el == null ? null : Studio.textRun(el);
		return r == null ? "" : r.text;
	}

	static function source(studio:Studio):String {
		var s = studio.selection();
		if (s == null) return "";
		studio.docs.version();
		return haxe.io.Path.withoutDirectory(s.file) + ":" + studio.docs.get(s.file).doc.lineCol(s.start).line;
	}
}
