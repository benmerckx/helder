package hxmc.ui.widgets;

import hxmc.ui.reactive.Signal;
import hxmc.ui.reactive.Reactive.signal;

// The widgets' colours by role, light or dark; Theme.current is the one
// they draw with (a signal: set it and every widget follows, its colours
// moving as they do on hover). An app paints its own surfaces with
// background and text, and follows the system with
// Theme.current.value = dark ? Theme.DARK : Theme.LIGHT (UiWindow.dark).
class Theme {
	public static final LIGHT = new Theme(false, {
		background: "#fafafa",
		text: "#18181b",
		muted: "#71717a",
		control: "#ffffff",
		controlHover: "#e4e4e7",
		controlPressed: "#d4d4d8",
		border: "#a1a1aa",
		borderMuted: "#d4d4d8",
		mark: "#71717a",
		accent: "#3b82f6",
		accentHover: "#2563eb",
		accentPressed: "#1d4ed8",
		accentText: "#1d4ed8",
		onAccent: "#ffffff",
		secondary: "#52525b",
		track: "#d4d4d8",
		subtle: "#e4e4e7",
		knob: "#ffffff",
		itemHover: "#f4f4f5",
		itemSelected: "#dbeafe",
		tooltip: "#27272a",
		onTooltip: "#ffffff",
		placeholder: "#00000066",
		selection: "#3b82f64d",
		caret: "#111111"
	});

	public static final DARK = new Theme(true, {
		background: "#18181b",
		text: "#f4f4f5",
		muted: "#a1a1aa",
		control: "#27272a",
		controlHover: "#3f3f46",
		controlPressed: "#52525b",
		border: "#52525b",
		borderMuted: "#3f3f46",
		mark: "#a1a1aa",
		accent: "#3b82f6",
		accentHover: "#60a5fa",
		accentPressed: "#2563eb",
		accentText: "#93c5fd",
		onAccent: "#ffffff",
		secondary: "#a1a1aa",
		track: "#52525b",
		subtle: "#3f3f46",
		knob: "#f4f4f5",
		itemHover: "#3f3f46",
		itemSelected: "#1e3a8a",
		tooltip: "#e4e4e7",
		onTooltip: "#18181b",
		placeholder: "#ffffff66",
		selection: "#3b82f666",
		caret: "#f4f4f5"
	});

	// the theme the widgets draw with
	public static final current:Signal<Theme> = signal(LIGHT);

	public final dark:Bool;
	// an app's own surfaces and text
	public final background:String;
	public final text:String;
	// muted text and signs (a select's arrow, a heading's small caps)
	public final muted:String;
	// a control's face (a button, a field, a panel), hovered, pressed; its border; a panel's lighter border
	public final control:String;
	public final controlHover:String;
	public final controlPressed:String;
	public final border:String;
	public final borderMuted:String;
	// an unchecked box's or radio's border
	public final mark:String;
	// the accent: filled buttons, checks, the chosen, the focus; hovered, pressed; as text (the chosen tab)
	public final accent:String;
	public final accentHover:String;
	public final accentPressed:String;
	public final accentText:String;
	public final onAccent:String;
	// secondary text (a tab not chosen, a note)
	public final secondary:String;
	// a switch's and a slider's track; a subtle surface (a progress bar's track, a panel's border); a switch's knob
	public final track:String;
	public final subtle:String;
	public final knob:String;
	// a menu's or list's item hovered, chosen
	public final itemHover:String;
	public final itemSelected:String;
	public final tooltip:String;
	public final onTooltip:String;
	// a text field's placeholder, selection, caret
	public final placeholder:String;
	public final selection:String;
	public final caret:String;

	public function new(dark:Bool, c:{background:String, text:String, muted:String, control:String, controlHover:String, controlPressed:String,
		border:String, borderMuted:String, mark:String, accent:String, accentHover:String, accentPressed:String, accentText:String, onAccent:String,
		secondary:String, track:String, subtle:String, knob:String, itemHover:String, itemSelected:String, tooltip:String, onTooltip:String,
		placeholder:String, selection:String, caret:String}) {
		this.dark = dark;
		background = c.background;
		text = c.text;
		muted = c.muted;
		control = c.control;
		controlHover = c.controlHover;
		controlPressed = c.controlPressed;
		border = c.border;
		borderMuted = c.borderMuted;
		mark = c.mark;
		accent = c.accent;
		accentHover = c.accentHover;
		accentPressed = c.accentPressed;
		accentText = c.accentText;
		onAccent = c.onAccent;
		secondary = c.secondary;
		track = c.track;
		subtle = c.subtle;
		knob = c.knob;
		itemHover = c.itemHover;
		itemSelected = c.itemSelected;
		tooltip = c.tooltip;
		onTooltip = c.onTooltip;
		placeholder = c.placeholder;
		selection = c.selection;
		caret = c.caret;
	}

	// the theme set from a reactive question (Theme.follow(() -> UiWindow.dark.value)): DARK when it says so
	public static function follow(dark:Void->Bool)
		hxmc.ui.reactive.Reactive.effect(() -> current.value = dark() ? DARK : LIGHT);

	// a colour of the theme made transparent (a fade's other end)
	public static inline function clear(c:String):String
		return c.substr(0, 7) + "00";
}
