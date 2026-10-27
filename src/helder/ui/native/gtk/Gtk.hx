package helder.ui.native.gtk;

import hxmc.unsafe.*;

// GTK 3 (libgtk-3.so.0, the dynamic glibc mode): the calls GtkBackend makes.
// Widgets, windows and providers are Ptr; gboolean is Int; gfloat Float32.
@:hxmc.c @:hxmc.lib("libgtk-3.so.0") extern class Gtk {
	static function gtk_init_check(argc:Ptr, argv:Ptr):Int;
	static function gtk_window_new(type:Int):Ptr;
	static function gtk_window_set_title(w:Ptr, title:Ptr):Void;
	static function gtk_window_set_default_size(w:Ptr, width:Int, height:Int):Void;
	static function gtk_fixed_new():Ptr;
	static function gtk_fixed_put(fixed:Ptr, w:Ptr, x:Int, y:Int):Void;
	static function gtk_fixed_move(fixed:Ptr, w:Ptr, x:Int, y:Int):Void;
	static function gtk_container_add(container:Ptr, w:Ptr):Void;
	static function gtk_widget_show(w:Ptr):Void;
	static function gtk_widget_realize(w:Ptr):Void;
	static function gtk_widget_show_all(w:Ptr):Void;
	static function gtk_widget_destroy(w:Ptr):Void;
	static function gtk_widget_set_size_request(w:Ptr, width:Int, height:Int):Void;
	static function gtk_widget_set_sensitive(w:Ptr, sensitive:Int):Void;
	static function gtk_widget_get_preferred_width(w:Ptr, min:Ptr<Int32>, natural:Ptr<Int32>):Void;
	static function gtk_widget_get_preferred_height(w:Ptr, min:Ptr<Int32>, natural:Ptr<Int32>):Void;
	static function gtk_widget_get_preferred_height_for_width(w:Ptr, width:Int, min:Ptr<Int32>, natural:Ptr<Int32>):Void;
	static function gtk_widget_get_allocated_width(w:Ptr):Int;
	static function gtk_widget_get_allocated_height(w:Ptr):Int;
	static function gtk_widget_get_style_context(w:Ptr):Ptr;
	static function gtk_widget_get_window(w:Ptr):Ptr;
	static function gtk_widget_create_pango_layout(w:Ptr, text:Ptr):Ptr;
	static function gtk_widget_translate_coordinates(src:Ptr, dst:Ptr, x:Int, y:Int, dx:Ptr<Int32>, dy:Ptr<Int32>):Int;
	static function gtk_style_context_add_provider(context:Ptr, provider:Ptr, priority:Int):Void;
	static function gtk_css_provider_new():Ptr;
	static function gtk_css_provider_load_from_data(provider:Ptr, data:Ptr, length:Int64, error:Ptr):Int;
	static function gtk_button_new_with_label(label:Ptr):Ptr;
	static function gtk_button_set_label(b:Ptr, label:Ptr):Void;
	static function gtk_button_clicked(b:Ptr):Void;
	static function gtk_label_new(text:Ptr):Ptr;
	static function gtk_label_set_text(l:Ptr, text:Ptr):Void;
	static function gtk_label_set_line_wrap(l:Ptr, wrap:Int):Void;
	static function gtk_label_set_xalign(l:Ptr, x:Float32):Void;
	static function gtk_label_set_yalign(l:Ptr, y:Float32):Void;
	static function gtk_label_set_justify(l:Ptr, justify:Int):Void;
	static function gtk_entry_new():Ptr;
	static function gtk_entry_set_text(e:Ptr, text:Ptr):Void;
	static function gtk_entry_get_text(e:Ptr):Ptr;
	static function gtk_entry_set_placeholder_text(e:Ptr, text:Ptr):Void;
	static function gtk_check_button_new_with_label(label:Ptr):Ptr;
	static function gtk_toggle_button_set_active(b:Ptr, active:Int):Void;
	static function gtk_toggle_button_get_active(b:Ptr):Int;
	static function gtk_scale_new_with_range(orientation:Int, min:Float, max:Float, step:Float):Ptr;
	static function gtk_scale_set_draw_value(s:Ptr, draw:Int):Void;
	static function gtk_range_set_range(r:Ptr, min:Float, max:Float):Void;
	static function gtk_range_set_increments(r:Ptr, step:Float, page:Float):Void;
	static function gtk_range_set_value(r:Ptr, value:Float):Void;
	static function gtk_range_get_value(r:Ptr):Float;
	static function gtk_progress_bar_new():Ptr;
	static function gtk_progress_bar_set_fraction(p:Ptr, fraction:Float):Void;
}

// text laid out as GtkLabel lays it out (GtkBackend.measureText)
@:hxmc.c @:hxmc.lib("libpango-1.0.so.0") extern class Pango {
	static function pango_layout_set_text(layout:Ptr, text:Ptr, length:Int):Void;
	static function pango_layout_set_width(layout:Ptr, width:Int):Void;
	static function pango_layout_set_wrap(layout:Ptr, wrap:Int):Void;
	static function pango_layout_set_font_description(layout:Ptr, desc:Ptr):Void;
	static function pango_layout_get_pixel_size(layout:Ptr, width:Ptr<Int32>, height:Ptr<Int32>):Void;
	static function pango_font_description_new():Ptr;
	static function pango_font_description_free(desc:Ptr):Void;
	static function pango_font_description_set_family(desc:Ptr, family:Ptr):Void;
	static function pango_font_description_set_absolute_size(desc:Ptr, size:Float):Void;
	static function pango_font_description_set_weight(desc:Ptr, weight:Int):Void;
	static function pango_font_description_set_style(desc:Ptr, style:Int):Void;
}

@:hxmc.c @:hxmc.lib("libgobject-2.0.so.0") extern class GObject {
	static function g_signal_connect_data(instance:Ptr, signal:Ptr, handler:Ptr, data:Ptr, destroy:Ptr, flags:Int):Int64;
	static function g_object_unref(o:Ptr):Void;
}

// (blocking iterations run in a safe region: other threads go on)
@:hxmc.c @:hxmc.lib("libglib-2.0.so.0") extern class GLib {
	static function g_main_context_iteration(context:Ptr, mayBlock:Int):Int;
}

// a window's pixels as a PNG file (tests)
@:hxmc.c @:hxmc.lib("libgdk-3.so.0") extern class Gdk {
	static function gdk_pixbuf_get_from_window(window:Ptr, x:Int, y:Int, width:Int, height:Int):Ptr;
}

@:hxmc.c @:hxmc.lib("libgdk_pixbuf-2.0.so.0") extern class GdkPixbuf {
	static function gdk_pixbuf_savev(pixbuf:Ptr, filename:Ptr, type:Ptr, keys:Ptr, values:Ptr, error:Ptr):Int;
}
