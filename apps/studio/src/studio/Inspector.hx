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
	// compact: the bottom sheet (Board's, over the canvas)
	public static function view(studio:Studio):View
		return sheet(studio);

	// the desktop's card at the right: what is selected, its sections; else
	// the frame in focus, else the project
	public static function card(studio:Studio):View
		return <view tag="inspector" grow={1} min-height={0}>
			<view tag="inspector-head" padding="14 14 12" shrink={0} row-gap={3}>
				<view direction="row" align-items="center" column-gap={8}>
					<image src={headIcon(studio)} width={Theme.ICON} height={Theme.ICON} color={c("accent")}/>
					<text tag="inspector-title" font-weight={Theme.MEDIUM} max-lines={1} text-overflow="ellipsis">{title(studio)}</text>
				</view>
				<text font-size={Theme.SMALL} color={c("fg3")} max-lines={1} text-overflow="ellipsis">{subtitle(studio)}</text>
			</view>
			<scroll grow={1} min-height={0}>{fields(studio)}</scroll>
		</view>;

	// compact: a bottom sheet over the canvas, sliding up when a screen is
	// zoomed into; its handle (a tap) opens and closes it, the screen
	// fitted above it on the camera's spring, its height on motion's
	static function sheet(studio:Studio):View
		return <view tag="inspector" slot="sheet" border-width="1 0 0 0" position="absolute" left={0} right={0} bottom={0} height={studio.sheetOpen() ? Theme.SHEET : Theme.SHEET_PEEK}
			overflow="hidden" transition="slide-up(80) fade" motion="snappy" onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<view:button tag="sheet-toggle" role="button" label={studio.sheetOpen() ? "Close the inspector" : "Open the inspector"} focusable
				align-items="center" row-gap={8} padding="8 0 6" cursor="pointer" onPress={() -> studio.toggleSheet()}>
				<view slot="sheet-handle"/>
				<text color={c("fg2")} font-size={Theme.SMALL}>{title(studio)}</text>
			</view:button>
			<scroll grow={1} min-height={0}>{fields(studio)}</scroll>
		</view>;

	static function headIcon(studio:Studio):helder.ui.Svg
		return studio.selection() != null ? (hasText(studio) ? Icons.font : Icons.element) : studio.focused() != null ? Icons.frame : Icons.folder;

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

	// a section: its icon and header, its rows
	static function section(tag:String, icon:helder.ui.Svg, title:String, rows:View):View
		return <view tag={tag} slot="section">
			<view slot="section-head"><image src={icon} width={12} height={12}/><text>{title}</text></view>
			{rows}
		</view>;

	static function fields(studio:Studio):View {
		return <view>
			<Show when={studio.selection() != null} fallback={<view slot="section">
				<text color={c("fg3")} font-size={Theme.SMALL} padding="2 0">{empty(studio)}</text>
			</view>}>
				{section("section-layout", Icons.ruler, "Layout", <view>
					{field(studio, "width", "Width", true)}
					{field(studio, "height", "Height", true)}
					{field(studio, "padding", "Padding", true)}
					{field(studio, gapName(studio), "Gap", true)}
				</view>)}
				{section("section-style", Icons.palette, "Style", <view>
					{field(studio, "background", "Fill", false)}
					{field(studio, "radius", "Radius", true)}
					{field(studio, "color", "Color", false)}
				</view>)}
				<Show when={hasText(studio)}>
					{section("section-text", Icons.textCursor, "Text", <view slot="field">
						<text slot="field-label" cursor="default">Text</text>
						<field tag="field-text" slot="field-input" label="Text" value={textValue(studio)} onInput={e -> studio.setText(e.text)}
							onBlur={() -> studio.endGesture()}/>
					</view>)}
				</Show>
				{section("section-source", Icons.code, "Source", <view slot="field">
					<text slot="field-label" cursor="default">File</text>
					<view grow={1}/>
					<text tag="inspector-source" color={c("fg2")}>{source(studio)}</text>
				</view>)}
			</Show>
		</view>;
	}

	static function empty(studio:Studio):String {
		var verb = studio.compact() ? "Tap" : "Click";
		return studio.focused() != null ? '$verb a part of the frame to select it.' : '$verb a frame to select it, or choose one in the sidebar.';
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
