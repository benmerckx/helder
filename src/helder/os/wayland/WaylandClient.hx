package helder.os.wayland;

import hxmc.unsafe.*;

// libwayland-client.so.0, loaded at run time (helder.os.Dl: no Wayland, no
// dependency): the connection, its event queue, and the proxy calls the
// generated bindings make (marshalling by wl_argument arrays, one
// dispatcher for every proxy). libwayland 1.20's wl_proxy_marshal_array_flags.
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class WaylandClient {
	static function wl_display_connect(name:Ptr):Ptr;
	static function wl_display_disconnect(d:Ptr):Void;
	static function wl_display_get_fd(d:Ptr):Int;
	static function wl_display_dispatch_pending(d:Ptr):Int;
	static function wl_display_roundtrip(d:Ptr):Int;
	static function wl_display_flush(d:Ptr):Int;
	static function wl_display_prepare_read(d:Ptr):Int;
	static function wl_display_read_events(d:Ptr):Int;
	static function wl_display_cancel_read(d:Ptr):Void;
	static function wl_display_get_error(d:Ptr):Int;
	static function wl_proxy_marshal_array_flags(p:Ptr, opcode:Int, iface:Ptr, version:Int, flags:Int, args:Ptr<Int64>):Ptr;
	static function wl_proxy_add_dispatcher(p:Ptr, f:Ptr, data:Ptr, user:Ptr):Int;
	static function wl_proxy_get_version(p:Ptr):Int;
	static function wl_proxy_destroy(p:Ptr):Void;
}

// libwayland-egl.so.1: an EGL window of a surface (EGLNativeWindowType on Wayland)
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class WaylandEgl {
	static function wl_egl_window_create(surface:Ptr, width:Int, height:Int):Ptr;
	static function wl_egl_window_resize(w:Ptr, width:Int, height:Int, dx:Int, dy:Int):Void;
	static function wl_egl_window_destroy(w:Ptr):Void;
}

// libwayland-cursor.so.0: the cursor theme's images as wl_buffers (where
// the compositor has no cursor-shape protocol)
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class WaylandCursor {
	static function wl_cursor_theme_load(name:Ptr, size:Int, shm:Ptr):Ptr;
	static function wl_cursor_theme_get_cursor(theme:Ptr, name:Ptr):Ptr;
	static function wl_cursor_image_get_buffer(image:Ptr):Ptr;
}

// libxkbcommon.so.0: the keymap the compositor sends, a key's KeySym and text
@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
class Xkb {
	static function xkb_context_new(flags:Int):Ptr;
	static function xkb_keymap_new_from_string(ctx:Ptr, s:Ptr, format:Int, flags:Int):Ptr;
	static function xkb_keymap_unref(k:Ptr):Void;
	static function xkb_keymap_mod_get_index(k:Ptr, name:Ptr):Int;
	static function xkb_keymap_key_get_syms_by_level(k:Ptr, key:Int, layout:Int, level:Int, syms:Ptr):Int;
	static function xkb_keymap_key_repeats(k:Ptr, key:Int):Int;
	static function xkb_state_new(k:Ptr):Ptr;
	static function xkb_state_unref(s:Ptr):Void;
	static function xkb_state_update_mask(s:Ptr, depressed:Int, latched:Int, locked:Int, dl:Int, ll:Int, group:Int):Int;
	static function xkb_state_key_get_utf8(s:Ptr, key:Int, buf:Ptr, size:Int64):Int;
	static function xkb_state_key_get_layout(s:Ptr, key:Int):Int;
}

// the C library's calls for shared memory and waiting
@:hxmc.c @:hxmc.lib("libc.so.6") extern class WlLibc {
	static function memfd_create(name:Ptr, flags:Int):Int;
	static function ftruncate(fd:Int, size:Int64):Int;
	@:hxmc.fast static function mmap(addr:Ptr, size:Int64, prot:Int, flags:Int, fd:Int, offset:Int64):Ptr;
	@:hxmc.fast static function munmap(addr:Ptr, size:Int64):Int;
	static function ppoll(fds:Ptr, n:Int64, timeout:Ptr, sigmask:Ptr):Int;

}
