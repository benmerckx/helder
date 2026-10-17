package hxmc.ui.native.gtk;

import hxmc.ui.*;
import hxmc.ui.native.*;
import hxmc.ui.native.gtk.Gtk;
import hxmc.unsafe.*;

// NativeBackend on GTK 3 (Linux, glibc mode): a GtkWindow holding a
// GtkFixed where the widgets are put at their positions (their size
// requested as the layout's); GtkButton, GtkLabel (wrapping, its font and
// colour through a CSS provider), GtkEntry, GtkCheckButton, GtkScale,
// GtkProgressBar. Measured with GTK's preferred sizes. Signals come back
// through @:hxmc.callback functions, the widget's handle as their data;
// what update sets itself is not reported back.
class GtkBackend implements NativeBackend {
	static var started = false;
	static var nextHandle = 1;
	// by handle: the backend, the widget, its node
	static final backends = new Map<Int, GtkBackend>();

	final widgets = new Map<Int, Ptr>();
	final nodes = new Map<Int, Node>();
	final providers = new Map<Int, Ptr>();
	var host:Null<NativeHost>;
	var window = Ptr.nil();
	var fixed = Ptr.nil();
	var width = 0;
	var height = 0;
	var open = false;
	// (update's own changes: no signal reported)
	var updating = false;
	// a Pango layout measuring text
	var layout = Ptr.nil();
	var windowHandle = 0;

	public function new() {
		if (!started) {
			if (Gtk.gtk_init_check(Ptr.nil(), Ptr.nil()) == 0) throw "hxmc.ui.native: GTK cannot open the display (DISPLAY=" + Sys.getEnv("DISPLAY") + ")";
			started = true;
		}
	}

	public function openWindow(title:String, w:Int, h:Int, host:NativeHost) {
		this.host = host;
		width = w;
		height = h;
		window = Gtk.gtk_window_new(0);
		Arena.scoped(a -> Gtk.gtk_window_set_title(window, a.cstring(title)));
		Gtk.gtk_window_set_default_size(window, w, h);
		fixed = Gtk.gtk_fixed_new();
		Gtk.gtk_container_add(window, fixed);
		windowHandle = nextHandle++;
		backends.set(windowHandle, this);
		connect(window, "delete-event", Callback.addr(onDelete), windowHandle);
		connect(fixed, "size-allocate", Callback.addr(onAllocate), windowHandle);
		Gtk.gtk_widget_show_all(window);
		open = true;
		layout = Gtk.gtk_widget_create_pango_layout(window, Ptr.nil());
	}

	public function closeWindow() {
		if (!open) return;
		open = false;
		Gtk.gtk_widget_destroy(window);
	}

	public function windowWidth():Int
		return width;

	public function windowHeight():Int
		return height;

	static function connect(w:Ptr, signal:String, handler:Ptr, handle:Int)
		Arena.scoped(a -> GObject.g_signal_connect_data(w, a.cstring(signal), handler, Ptr.ofI64(handle), Ptr.nil(), 0));

	public function create(n:Node):Int {
		var h = nextHandle++;
		var w = if (Std.isOfType(n, Control)) {
			var c:Control = cast n;
			switch c.kind {
				case Button:
					var b = Gtk.gtk_button_new_with_label(Ptr.nil());
					connect(b, "clicked", Callback.addr(onClicked), h);
					b;
				case Label:
					Gtk.gtk_label_new(Ptr.nil());
				case TextField:
					var e = Gtk.gtk_entry_new();
					connect(e, "changed", Callback.addr(onChanged), h);
					connect(e, "activate", Callback.addr(onActivate), h);
					e;
				case CheckBox:
					var b = Gtk.gtk_check_button_new_with_label(Ptr.nil());
					connect(b, "toggled", Callback.addr(onToggled), h);
					b;
				case Slider:
					var s = Gtk.gtk_scale_new_with_range(0, 0, 1, 0.01);
					Gtk.gtk_scale_set_draw_value(s, 0);
					connect(s, "value-changed", Callback.addr(onValueChanged), h);
					s;
				case Progress:
					Gtk.gtk_progress_bar_new();
			}
		} else {
			var l = Gtk.gtk_label_new(Ptr.nil());
			Gtk.gtk_label_set_line_wrap(l, 1);
			Gtk.gtk_label_set_yalign(l, 0);
			l;
		}
		widgets.set(h, w);
		nodes.set(h, n);
		backends.set(h, this);
		Gtk.gtk_fixed_put(fixed, w, 0, 0);
		Gtk.gtk_widget_show(w);
		// (realized now: the theme's padding counts in what it measures)
		Gtk.gtk_widget_realize(w);
		return h;
	}

	public function update(h:Int, n:Node) {
		var w = widgets.get(h);
		if (w == null) return;
		updating = true;
		Arena.scoped(a -> {
			if (Std.isOfType(n, Control)) {
				var c:Control = cast n;
				switch c.kind {
					case Button:
						Gtk.gtk_button_set_label(w, a.cstring(c.text));
					case Label:
						Gtk.gtk_label_set_text(w, a.cstring(c.text));
					case TextField:
						if (text(Gtk.gtk_entry_get_text(w)) != c.text) Gtk.gtk_entry_set_text(w, a.cstring(c.text));
						Gtk.gtk_entry_set_placeholder_text(w, a.cstring(c.placeholder));
					case CheckBox:
						Gtk.gtk_button_set_label(w, a.cstring(c.text));
						Gtk.gtk_toggle_button_set_active(w, c.checked ? 1 : 0);
					case Slider:
						Gtk.gtk_range_set_range(w, c.min, c.max > c.min ? c.max : c.min + 1);
						Gtk.gtk_range_set_increments(w, c.step > 0 ? c.step : (c.max - c.min) / 100, (c.max - c.min) / 10);
						Gtk.gtk_range_set_value(w, c.value);
					case Progress:
						Gtk.gtk_progress_bar_set_fraction(w, c.value < 0 ? 0 : c.value > 1 ? 1 : c.value);
				}
				Gtk.gtk_widget_set_sensitive(w, c.enabled ? 1 : 0);
			} else if (Std.isOfType(n, TextNode)) {
				var t:TextNode = cast n;
				Gtk.gtk_label_set_text(w, a.cstring(t.text));
				var align = t.textAlign();
				Gtk.gtk_label_set_xalign(w, align == Center ? 0.5 : align == Right ? 1 : 0);
				// (GtkJustification: left 0, right 1, center 2)
				Gtk.gtk_label_set_justify(w, align == Center ? 2 : align == Right ? 1 : 0);
				style(h, w, css(t.font(), t.textColor()));
			}
		});
		updating = false;
	}

	// a widget's CSS (its provider made once)
	function style(h:Int, w:Ptr, rules:String) {
		var p = providers.get(h);
		if (p == null) {
			p = Gtk.gtk_css_provider_new();
			providers.set(h, p);
			Gtk.gtk_style_context_add_provider(Gtk.gtk_widget_get_style_context(w), p, 800);
		}
		Arena.scoped(a -> Gtk.gtk_css_provider_load_from_data(p, a.cstring(rules), -1, Ptr.nil()));
	}

	static function css(f:Font, c:Color):String {
		var color = 'rgba(${c.r}, ${c.g}, ${c.b}, ${Math.round(c.a / 255 * 1000) / 1000})';
		return '* { font-family: "${f.family}"; font-size: ${f.size}px; font-weight: ${f.weight}; font-style: ${f.italic ? "italic" : "normal"}; color: $color; }';
	}

	public function place(h:Int, x:Float, y:Float, w:Float, ht:Float) {
		var widget = widgets.get(h);
		if (widget == null) return;
		Gtk.gtk_fixed_move(fixed, widget, Math.round(x), Math.round(y));
		Gtk.gtk_widget_set_size_request(widget, Math.round(Math.max(1, w)), Math.round(Math.max(1, ht)));
	}

	public function destroy(h:Int) {
		var w = widgets.get(h);
		if (w == null) return;
		Gtk.gtk_widget_destroy(w);
		widgets.remove(h);
		nodes.remove(h);
		backends.remove(h);
		var p = providers.get(h);
		if (p != null) {
			GObject.g_object_unref(p);
			providers.remove(h);
		}
	}

	public function measure(c:Control, width:Float):Size {
		var w = widgets.get(c.handle);
		if (w == null) return new Size(0, 0);
		return Arena.scopedValue(a -> {
			var min:Ptr<Int32> = a.alloc(4), nat:Ptr<Int32> = a.alloc(4);
			Gtk.gtk_widget_get_preferred_width(w, min, nat);
			var pw = nat.value;
			Gtk.gtk_widget_get_preferred_height(w, min, nat);
			new Size(pw, nat.value);
		});
	}

	// (Pango, as GtkLabel: the font's family, size in pixels, weight and
	// style; wrapped at words, then characters, within maxWidth)
	public function measureText(s:String, f:Font, maxWidth:Float):Size {
		return Arena.scopedValue(a -> {
			var d = Pango.pango_font_description_new();
			Pango.pango_font_description_set_family(d, a.cstring(f.family));
			Pango.pango_font_description_set_absolute_size(d, f.size * 1024);
			Pango.pango_font_description_set_weight(d, f.weight);
			Pango.pango_font_description_set_style(d, f.italic ? 2 : 0);
			Pango.pango_layout_set_font_description(layout, d);
			Pango.pango_font_description_free(d);
			Pango.pango_layout_set_text(layout, a.cstring(s), -1);
			Pango.pango_layout_set_wrap(layout, 2);
			Pango.pango_layout_set_width(layout, Math.isNaN(maxWidth) ? -1 : Std.int(Math.max(1, maxWidth) * 1024));
			var w:Ptr<Int32> = a.alloc(4), h:Ptr<Int32> = a.alloc(4);
			Pango.pango_layout_get_pixel_size(layout, w, h);
			new Size(w.value, h.value);
		});
	}

	public function pump(block:Bool):Bool {
		if (!open) return false;
		if (block) GLib.g_main_context_iteration(Ptr.nil(), 1);
		while (open && GLib.g_main_context_iteration(Ptr.nil(), 0) != 0) {}
		return open;
	}

	// the widget's position in the window and size, as GTK has allocated them (tests)
	public function allocation(h:Int):Array<Int> {
		var w = widgets.get(h);
		if (w == null) return [];
		return Arena.scopedValue(a -> {
			var x:Ptr<Int32> = a.alloc(4), y:Ptr<Int32> = a.alloc(4);
			Gtk.gtk_widget_translate_coordinates(w, fixed, 0, 0, x, y);
			[x.value, y.value, Gtk.gtk_widget_get_allocated_width(w), Gtk.gtk_widget_get_allocated_height(w)];
		});
	}

	// the widget's pointer (tests drive it with GTK's own calls)
	public function widget(h:Int):Ptr
		return widgets.get(h);

	// the window's pixels saved as a PNG file (tests)
	public function screenshot(path:String):Bool {
		var pb = Gdk.gdk_pixbuf_get_from_window(Gtk.gtk_widget_get_window(window), 0, 0, width, height);
		if (pb.isNull()) return false;
		var ok = Arena.scopedValue(a -> GdkPixbuf.gdk_pixbuf_savev(pb, a.cstring(path), a.cstring("png"), Ptr.nil(), Ptr.nil(), Ptr.nil())) != 0;
		GObject.g_object_unref(pb);
		return ok;
	}

	public static function text(p:Ptr):String {
		if (p.isNull()) return "";
		var s:Ptr<UInt8> = p;
		return (s : CString).toString();
	}

	// --- signals ---

	static function control(data:Ptr):Null<Control> {
		var h = data.toI64().toInt();
		var b = backends.get(h);
		if (b == null || b.updating) return null;
		var n = b.nodes.get(h);
		return Std.isOfType(n, Control) ? cast n : null;
	}

	@:hxmc.callback static function onClicked(w:Ptr, data:Ptr):Void {
		var c = control(data);
		if (c != null) c.platformClick();
	}

	@:hxmc.callback static function onChanged(w:Ptr, data:Ptr):Void {
		var c = control(data);
		if (c != null) c.platformText(text(Gtk.gtk_entry_get_text(w)));
	}

	@:hxmc.callback static function onActivate(w:Ptr, data:Ptr):Void {
		var c = control(data);
		if (c != null) c.platformSubmit();
	}

	@:hxmc.callback static function onToggled(w:Ptr, data:Ptr):Void {
		var c = control(data);
		if (c != null) c.platformChecked(Gtk.gtk_toggle_button_get_active(w) != 0);
	}

	@:hxmc.callback static function onValueChanged(w:Ptr, data:Ptr):Void {
		var c = control(data);
		if (c != null) c.platformValue(Gtk.gtk_range_get_value(w));
	}

	@:hxmc.callback static function onDelete(w:Ptr, event:Ptr, data:Ptr):Int {
		var b = backends.get(data.toI64().toInt());
		if (b != null) {
			b.open = false;
			if (b.host != null) @:privateAccess b.host.windowClosed();
		}
		// (GTK destroys the window)
		return 0;
	}

	// the container's allocation (x, y, width, height: four ints)
	@:hxmc.callback static function onAllocate(w:Ptr, allocation:Ptr<Int32>, data:Ptr):Void {
		var b = backends.get(data.toI64().toInt());
		if (b == null) return;
		var nw = allocation[2], nh = allocation[3];
		if (nw != b.width || nh != b.height) {
			b.width = nw;
			b.height = nh;
			if (b.host != null) @:privateAccess b.host.windowResized();
		}
	}
}
