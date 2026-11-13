package studio;

import helder.ui.*;
import helder.ui.gesture.Gesture;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.ui.widgets.WindowButtons.WindowControls;
import studio.Theme.c;

using StringTools;

// The inspector, while a screen is zoomed into: the selected node's layout
// (width, height, padding, gap), style (background, colour, radius) and
// text, each read from its element in the source (helder.syntax) and
// written back there (Studio.setAttribute: an attribute set or added, the
// file's formatting kept, one history). A live literal's change shows in
// the screens' next frame (patched, then saved); another builds. A number's
// label scrubs it: dragged left or right, a point per two. Paper's way:
// each value a short field, its label inside, two to a row.
class Inspector implements Markup {
	// the desktop's panel at the right (compact: its sheet): what is selected, its sections; else
	// the frame in focus, else the project
	// (top: the window's top right; its buttons there where the app draws them, Shell.controlsRight)
	public static function card(studio:Studio, top = false):View {
		var controls = () -> top && Shell.controlsRight();
		return <view tag="inspector" grow={1} min-height={0}>
			<view tag="inspector-head" direction="row" align-items="center" column-gap={6} height={Theme.HEADER} drag-region={top}
				padding={'0 ${controls() ? 0 : Theme.PAD} 0 ${Theme.PAD}'} shrink={0}>
				<image src={headIcon(studio)} width={Theme.ICON_S} height={Theme.ICON_S} color={c("accent-ink")} shrink={0}/>
				<text tag="inspector-title" font-weight={Theme.MEDIUM} shrink={1} min-width={0} max-lines={1} text-overflow="ellipsis">{title(studio)}</text>
				<view grow={1}/>
				<text tag="inspector-source" font-family={studio.selection() != null ? Theme.CODE : Theme.UI} font-size={Theme.SMALL} color={c("fg3")} shrink={0} max-lines={1}>{subtitle(studio)}</text>
				{top ? <WindowControls side="end"/> : null}
			</view>
			<scroll grow={1} min-height={0}>{fields(studio)}</scroll>
		</view>;
	}

	static function headIcon(studio:Studio):helder.ui.Svg {
		var s = studio.selection(), f = studio.focused(), frame = f == null ? null : studio.project?.screen(f);
		if (s != null && frame != null && frame.start == s.start) return Icons.frame;
		return s != null ? (hasText(studio) ? Icons.font : Icons.element) : f != null ? Icons.frame : Icons.folder;
	}

	static function title(studio:Studio):String {
		var s = studio.selection(), f = studio.focused();
		var frame = f == null ? null : studio.project?.screen(f);
		if (s != null && frame != null && frame.start == s.start) return frame.label;
		if (s != null) return s.tag;
		if (f != null) {
			var info = studio.project?.screen(f);
			return info == null ? f : info.label;
		}
		return studio.project == null ? "helder studio" : studio.project.name;
	}

	static function subtitle(studio:Studio):String {
		var s = studio.selection(), f = studio.focused();
		if (s != null) return source(studio);
		var info = f == null ? null : studio.project?.screen(f);
		if (info != null) return kind(info) + " · " + Math.round(info.width > 0 ? info.width : 390) + " × " + Math.round(info.height > 0 ? info.height : 844);
		var p = studio.project;
		return p == null ? "" : p.screens.length + " frames";
	}

	static function kind(info:Project.ScreenInfo):String
		return switch info.source {
			case Design(_): "Design";
			case Story(_): "Story";
			case App: "App";
		}

	// a section: its header (a word), its rows
	static function section(tag:String, title:String, rows:View):View
		return <view tag={tag} slot="section">
			<view slot="section-head"><text>{title}</text></view>
			{rows}
		</view>;

	// the fields: two numbers to a row (a label inside each), a colour's a row with its swatch
	static function fields(studio:Studio):View {
		return <view>
			<Show when={studio.selection() != null} fallback={<view slot="section" padding={Theme.PAD}>
				<text color={c("fg3")} font-size={Theme.SMALL}>{empty(studio)}</text>
			</view>}>
				{section("section-layout", "Layout", <view row-gap={6}>
					<Show when={!hasText(studio)}>{direction(studio)}</Show>
					<view slot="fields">{field(studio, "width", "W", true)}{field(studio, "height", "H", true)}</view>
					<view slot="fields">{field(studio, "padding", "Padding", true)}{field(studio, gapName(studio), "Gap", true)}</view>
				</view>)}
				{section("section-style", "Style", <view row-gap={6}>
					<view slot="fields">{field(studio, "background", "Fill", false)}</view>
					<view slot="fields">{field(studio, "color", "Color", false)}</view>
					<view slot="fields">{field(studio, "radius", "Radius", true)}<view grow={1} basis={0}/></view>
				</view>)}
				<Show when={hasText(studio)}>
					{section("section-text", "Text", <view slot="field">
						<field tag="field-text" slot="field-input" label="Text" value={textValue(studio)} onInput={e -> studio.setText(e.text)}
							onBlur={() -> studio.endGesture()}/>
					</view>)}
				</Show>
			</Show>
		</view>;
	}

	// the layout's direction: a column (helder.ui's default) or a row
	static function direction(studio:Studio):View {
		function item(v:String, label:String):View
			return <view:button tag={"direction-" + v} slot="seg-item" grow={1} role="button" label={label} focusable
				data-on={(value(studio, "direction") == "row" ? "row" : "column") == v ? "true" : "false"} onPress={() -> {
					if (value(studio, "direction") == "" && v == "column") return;
					studio.setAttribute("direction", v);
					studio.endGesture();
				}}><text>{label}</text></view:button>;
		return <view tag="field-direction" slot="seg">{item("column", "Column")}{item("row", "Row")}</view>;
	}

	static function empty(studio:Studio):String {
		var verb = studio.compact() ? "Tap" : "Click";
		return studio.focused() != null ? '$verb a part of the frame to select it.' : '$verb a frame to select it, or choose one in the sidebar.';
	}

	// one attribute's field: its label inside (a number's scrubs it), a colour's swatch, its value as written
	static function field(studio:Studio, name:String, label:String, number:Bool):View {
		var start = 0.0;
		return <view tag={"field-" + name} slot="field">
			<text tag={"scrub-" + name} slot="field-label" cursor={number ? "ew-resize" : "default"} onPan={g -> {
				if (!number) return;
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
			<Show when={!number && value(studio, name) != ""}><view slot="swatch" background={swatch(value(studio, name))}/></Show>
			<field tag={"input-" + name} slot="field-input" label={label} value={value(studio, name)} placeholder={placeholder(studio, name)}
				onInput={e -> if (valid(name, e.text, number)) studio.setAttribute(name, e.text)}
				onKeyDown={e -> if (e.key == Key.ENTER) studio.endGesture()} onBlur={() -> studio.endGesture()}/>
		</view>;
	}

	// (a colour's swatch: what it is written as, else none)
	static function swatch(v:String):Color
		return v == "" ? Color.TRANSPARENT : try Color.parse(v) catch (_:Dynamic) Color.TRANSPARENT;

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
