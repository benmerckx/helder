package helder.os.wayland;

import helder.os.Event;
import helder.os.wayland.WaylandClient;
import helder.os.wayland.protocol.WaylandProtocol;
import helder.os.wayland.protocol.XdgShellProtocol;
import helder.os.wayland.protocol.XdgDecorationUnstableV1Protocol;
import helder.os.wayland.protocol.ViewporterProtocol;
import helder.os.wayland.protocol.FractionalScaleV1Protocol;
import helder.os.wayland.protocol.CursorShapeV1Protocol;
import hxmc.unsafe.*;

// helder.os.Window on Wayland (Linux with WAYLAND_DISPLAY set and
// libwayland-client there; X11 otherwise): one connection for the process,
// its globals bound from the registry. A window is a wl_surface with an
// xdg_toplevel; its Surface (kind Wayland) is the wl_display and a
// wl_egl_window (libwayland-egl) that GL's EGL renders to. Sizes are the
// buffer's pixels: the points the compositor configures times the scale
// (wp_fractional_scale_v1's, the buffer at that size and wp_viewporter's
// destination in points; else wl_surface's preferred_buffer_scale, an
// integer). Decorations: the compositor's where it offers
// zxdg_decoration_manager_v1 and agrees to draw them, else helder's own: a
// bar of 30 points above the content (a wl_subsurface of wl_shm pixels:
// minimise, maximise and close at the right, a press elsewhere moves the
// window, a double press maximises), no title text in it. Input: the
// seat's keyboard (xkbcommon: the keymap the compositor sends, KeySyms as
// X11's, the text a key types, its repeat), pointer (buttons, the wheel's
// value120 notches or a touchpad's pixels; cursor-shape-v1's shapes, else
// libwayland-cursor's theme) and touch (helder.os.Pointers). wl_data_device:
// the clipboard's text (offered as text/plain;charset=utf-8, read from the
// selection's offer through a pipe) and files dropped (text/uri-list).
// Events come from libwayland's dispatch into a queue, then App's callback.
@:allow(helder.os)
class WaylandWindow {
	// the connection and its globals (nil: not connected)
	static var display = Ptr.nil();
	static var registry:WlRegistry = Ptr.nil();
	static var compositor:WlCompositor = Ptr.nil();
	static var subcompositor:WlSubcompositor = Ptr.nil();
	static var shm:WlShm = Ptr.nil();
	static var wmBase:XdgWmBase = Ptr.nil();
	static var seat:WlSeat = Ptr.nil();
	static var pointer:WlPointer = Ptr.nil();
	static var keyboard:WlKeyboard = Ptr.nil();
	static var touch:WlTouch = Ptr.nil();
	static var dataManager:WlDataDeviceManager = Ptr.nil();
	static var dataDevice:WlDataDevice = Ptr.nil();
	static var decorations:ZxdgDecorationManagerV1 = Ptr.nil();
	static var viewporter:WpViewporter = Ptr.nil();
	static var fractional:WpFractionalScaleManagerV1 = Ptr.nil();
	static var cursorShapes:WpCursorShapeManagerV1 = Ptr.nil();
	static var cursorDevice:WpCursorShapeDeviceV1 = Ptr.nil();
	static var compositorVersion = 0;
	// (each output's integer scale, by its proxy: a surface's before wl_surface's preferred_buffer_scale, version 6)
	static final outputScales:Map<String, Int> = [];
	static final open:Array<WaylandWindow> = [];
	// the events made by the dispatch, handed on by poll (a pool of Events)
	static final queue:Array<Event> = [];
	static final pool:Array<Event> = [];
	// (whether the Wayland back end is the one: chosen once)
	static var decided = false;
	static var chosen = false;

	// the input's state: the windows the pointer and the keyboard are in,
	// the last serials, the pointer's place (points), the modifiers
	static var pointerIn:Null<WaylandWindow> = null;
	static var pointerOnBar = false;
	static var keyboardIn:Null<WaylandWindow> = null;
	static var pointerSerial = 0;
	static var inputSerial = 0;
	static var px = 0.0;
	static var py = 0.0;
	static var mods = 0;
	static var buttonsDown = 0;
	// (a frame's scroll: pixels and wheel notches in 120ths)
	static var scrollX = 0.0;
	static var scrollY = 0.0;
	static var scroll120X = 0;
	static var scroll120Y = 0;
	// xkbcommon's context, keymap, state; the modifiers' indices
	static var xkbContext = Ptr.nil();
	static var xkbKeymap = Ptr.nil();
	static var xkbState = Ptr.nil();
	static var modShift = -1;
	static var modControl = -1;
	static var modAlt = -1;
	static var modSuper = -1;
	// key repeat: per second, the delay (ms); the key repeating, when next
	static var repeatRate = 25;
	static var repeatDelay = 600;
	static var repeatKey = -1;
	static var repeatAt = 0.0;
	// the clipboard: this process's text (null: not the owner), its source;
	// the selection's offer; the offers' MIME types
	static var clipboardText:Null<String> = null;
	static var clipboardSource:WlDataSource = Ptr.nil();
	static var selectionOffer:WlDataOffer = Ptr.nil();
	static final offerTypes:Map<String, Array<String>> = [];
	// a drag over a window: its offer, the window, where (points)
	static var dragOffer:WlDataOffer = Ptr.nil();
	static var dragWindow:Null<WaylandWindow> = null;
	static var dragSerial = 0;
	static var dragX = 0.0;
	static var dragY = 0.0;
	// libwayland-cursor's theme (nil: none), the cursor's surface
	static var cursorTheme = Ptr.nil();
	static var cursorSurface:WlSurface = Ptr.nil();
	static var cursorNow:Cursor = Default;

	final owner:Window;
	var surface:Null<Surface> = null;
	var wlSurface:WlSurface = Ptr.nil();
	var xdgSurface:XdgSurface = Ptr.nil();
	var toplevel:XdgToplevel = Ptr.nil();
	var decoration:ZxdgToplevelDecorationV1 = Ptr.nil();
	var viewport:WpViewport = Ptr.nil();
	var fractionalScale:WpFractionalScaleV1 = Ptr.nil();
	var egl = Ptr.nil();
	// the size in points (the content: the bar not in it), the scale (120ths: 120 is 1)
	var pointsW:Int;
	var pointsH:Int;
	var scale120 = 120;
	var configured = false;
	var fullscreen = false;
	var maximized = false;
	var activated = false;
	// the compositor's configure, waiting for its ack: size in points (0: ours), states
	var pendingW = 0;
	var pendingH = 0;
	var pendingFullscreen = false;
	var pendingMaximized = false;
	var pendingActivated = false;
	var minW = 0;
	var minH = 0;
	var savedW = 0;
	var savedH = 0;
	// helder's decorations (false: the compositor's), the bar's surface, its buffer, the button under the pointer (-1: none)
	var drawsBar = true;
	var bar:WlSurface = Ptr.nil();
	var barSub:WlSubsurface = Ptr.nil();
	var barBuffer:WlBuffer = Ptr.nil();
	var barHover = -1;
	var barDrawn = "";
	var lastBarPress = 0.0;
	var listeners:Array<Int> = [];
	// (the outputs it is on; whether the compositor says its preferred scale itself)
	final entered:Array<String> = [];
	var preferred = false;

	function outputScale() {
		if (preferred || !fractionalScale.isNull()) return;
		var k = 1;
		for (o in entered) {
			var f = outputScales.get(o) ?? 1;
			if (f > k) k = f;
		}
		if (k * 120 != scale120) rescale(k * 120);
	}

	public static inline var BAR = 30;

	// Wayland is the back end: WAYLAND_DISPLAY (or WAYLAND_SOCKET) set, libwayland there, a connection made
	public static function active():Bool {
		if (decided) return chosen;
		decided = true;
		var env = Sys.getEnv("WAYLAND_DISPLAY"), sock = Sys.getEnv("WAYLAND_SOCKET");
		if ((env == null || env == "") && (sock == null || sock == "")) return chosen = false;
		if (Sys.getEnv("HELDER_X11") == "1") return chosen = false;
		chosen = try connect() catch (e:Dynamic) {
			Sys.stderr().writeString("helder.os: Wayland: " + Std.string(e) + "; X11 instead\n");
			false;
		}
		return chosen;
	}

	static function connect():Bool {
		var err = WaylandClient.load("libwayland-client.so.0");
		if (err != null) throw err;
		err = WaylandEgl.load("libwayland-egl.so.1");
		if (err != null) throw err;
		display = WaylandClient.wl_display_connect(Ptr.nil());
		if (display.isNull()) throw "cannot connect to " + Sys.getEnv("WAYLAND_DISPLAY");
		registry = (display : WlDisplay).getRegistry();
		var r = new WlRegistryEvents();
		r.global = global;
		registry.listen(r);
		WaylandClient.wl_display_roundtrip(display);
		// (the seat's capabilities, the outputs)
		WaylandClient.wl_display_roundtrip(display);
		if (compositor.isNull() || wmBase.isNull() || shm.isNull()) {
			WaylandClient.wl_display_disconnect(display);
			display = Ptr.nil();
			throw "the compositor has no " + (compositor.isNull() ? "wl_compositor" : wmBase.isNull() ? "xdg_wm_base" : "wl_shm");
		}
		if (Xkb.load("libxkbcommon.so.0") == null) xkbContext = Xkb.xkb_context_new(0);
		return true;
	}

	static function bind(name:Int, iface:Ptr, have:Int, want:Int):Ptr
		return registry.bind(name, iface, have < want ? have : want);

	static function global(name:Int, iface:Null<String>, version:Int) {
		switch iface {
			case "wl_compositor":
				compositorVersion = version < 6 ? version : 6;
				compositor = bind(name, WlCompositor.iface, version, 6);
			case "wl_subcompositor": subcompositor = bind(name, WlSubcompositor.iface, version, 1);
			case "wl_shm": shm = bind(name, WlShm.iface, version, 1);
			case "xdg_wm_base":
				wmBase = bind(name, XdgWmBase.iface, version, 5);
				var e = new XdgWmBaseEvents();
				e.ping = serial -> wmBase.pong(serial);
				wmBase.listen(e);
			case "wl_seat":
				if (!seat.isNull()) return;
				seat = bind(name, WlSeat.iface, version, 8);
				var e = new WlSeatEvents();
				e.capabilities = seatCapabilities;
				seat.listen(e);
			case "wl_output":
				var o:WlOutput = bind(name, WlOutput.iface, version, 3);
				var key = Std.string((o : Ptr).toI64());
				outputScales.set(key, 1);
				var e = new WlOutputEvents();
				e.scale = f -> outputScales.set(key, f);
				o.listen(e);
			case "wl_data_device_manager": dataManager = bind(name, WlDataDeviceManager.iface, version, 3);
			case "zxdg_decoration_manager_v1": decorations = bind(name, ZxdgDecorationManagerV1.iface, version, 1);
			case "wp_viewporter": viewporter = bind(name, WpViewporter.iface, version, 1);
			case "wp_fractional_scale_manager_v1": fractional = bind(name, WpFractionalScaleManagerV1.iface, version, 1);
			case "wp_cursor_shape_manager_v1": cursorShapes = bind(name, WpCursorShapeManagerV1.iface, version, 1);
			case _:
		}
		if (!seat.isNull() && !dataManager.isNull() && dataDevice.isNull()) {
			dataDevice = dataManager.getDataDevice(seat);
			listenDataDevice();
		}
	}

	// --- the seat

	static function seatCapabilities(caps:Int) {
		if (caps & 1 != 0 && pointer.isNull()) {
			pointer = seat.getPointer();
			var e = new WlPointerEvents();
			e.enter = (serial, s, x, y) -> {
				pointerSerial = serial;
				pointerIn = find(s);
				pointerOnBar = pointerIn == null && barOf(s) != null;
				if (pointerOnBar) pointerIn = barOf(s);
				px = x;
				py = y;
				applyCursor(serial);
				if (pointerIn != null && !pointerOnBar) motion();
			};
			e.leave = (serial, s) -> {
				if (pointerOnBar && pointerIn != null) pointerIn.hoverBar(-1);
				pointerIn = null;
				pointerOnBar = false;
			};
			e.motion = (time, x, y) -> {
				px = x;
				py = y;
				if (pointerIn == null) return;
				if (pointerOnBar) pointerIn.hoverBar(pointerIn.barButton(px)) else motion();
			};
			e.button = (serial, time, button, state) -> {
				inputSerial = serial;
				var w = pointerIn;
				if (w == null) return;
				if (pointerOnBar) {
					w.barPress(button, state == 1, serial);
					return;
				}
				// (BTN_LEFT 0x110, BTN_RIGHT 0x111, BTN_MIDDLE 0x112)
				var b = button == 0x110 ? 1 : button == 0x111 ? 3 : button == 0x112 ? 2 : 0;
				if (b == 0) return;
				var ev = take(w, state == 1 ? MouseDown : MouseUp);
				ev.button = b;
				ev.x = Math.round(px * w.scale());
				ev.y = Math.round(py * w.scale());
				ev.mods = mods;
			};
			e.axis = (time, axis, value) -> if (axis == 0) scrollY += value else scrollX += value;
			e.axisValue120 = (axis, v) -> if (axis == 0) scroll120Y += v else scroll120X += v;
			e.frame = () -> {
				var w = pointerIn;
				if (w != null && !pointerOnBar && (scrollX != 0 || scrollY != 0 || scroll120X != 0 || scroll120Y != 0)) {
					var ev = take(w, Scroll);
					var k = w.scale();
					// (a wheel's notch is 40 pixels, as helder's elsewhere; a touchpad's motion as given)
					ev.deltaX = scroll120X != 0 ? scroll120X / 120 * 40 : scrollX * k;
					ev.deltaY = scroll120Y != 0 ? scroll120Y / 120 * 40 : scrollY * k;
					ev.x = Math.round(px * k);
					ev.y = Math.round(py * k);
					ev.mods = mods;
				}
				scrollX = scrollY = 0;
				scroll120X = scroll120Y = 0;
			};
			pointer.listen(e);
			if (!cursorShapes.isNull()) cursorDevice = cursorShapes.getPointer(pointer);
		}
		if (caps & 2 != 0 && keyboard.isNull()) {
			keyboard = seat.getKeyboard();
			var e = new WlKeyboardEvents();
			e.keymap = keymap;
			e.enter = (serial, s, keys) -> keyboardIn = find(s);
			e.leave = (serial, s) -> {
				keyboardIn = null;
				repeatKey = -1;
			};
			e.key = (serial, time, key, state) -> {
				inputSerial = serial;
				keyEvent(key + 8, state == 1, false);
			};
			e.modifiers = (serial, depressed, latched, locked, group) -> {
				if (xkbState.isNull()) return;
				Xkb.xkb_state_update_mask(xkbState, depressed, latched, locked, 0, 0, group);
				var all = depressed | latched;
				mods = (bit(all, modShift) ? Mods.SHIFT : 0) | (bit(all, modControl) ? Mods.CONTROL : 0) | (bit(all, modAlt) ? Mods.ALT : 0)
					| (bit(all, modSuper) ? Mods.META : 0);
			};
			e.repeatInfo = (rate, delay) -> {
				repeatRate = rate;
				repeatDelay = delay;
			};
			keyboard.listen(e);
		}
		if (caps & 4 != 0 && touch.isNull()) {
			touch = seat.getTouch();
			var e = new WlTouchEvents();
			e.down = (serial, time, s, id, x, y) -> {
				inputSerial = serial;
				var w = find(s);
				if (w == null) return;
				var k = w.scale();
				var p = Pointers.press(w.owner, id, helder.os.PointerType.Touch, x * k, y * k, 1, time);
				if (p != null) Pointers.fill(take(w, PointerDown), PointerDown, p, 1, mods);
			};
			e.motion = (time, id, x, y) -> {
				var p = Pointers.find(id, helder.os.PointerType.Touch);
				if (p == null) return;
				var w = byWindow(p.window);
				var k = w == null ? 1.0 : w.scale();
				@:privateAccess p.moveTo(x * k, y * k, 1, time);
				if (w != null) Pointers.fill(take(w, PointerMove), PointerMove, p, 0, mods);
			};
			e.up = (serial, time, id) -> {
				var p = Pointers.find(id, helder.os.PointerType.Touch);
				if (p == null) return;
				Pointers.lift(p, false, time);
				var w = byWindow(p.window);
				if (w != null) Pointers.fill(take(w, PointerUp), PointerUp, p, 1, mods);
			};
			e.cancel = () -> for (w in open) {
				var t = haxe.Timer.stamp() * 1000;
				for (i in 1...16) {
					var p = Pointers.find(i, helder.os.PointerType.Touch);
					if (p == null) continue;
					Pointers.lift(p, true, t);
					Pointers.fill(take(w, PointerCancel), PointerCancel, p, 0, mods);
				}
			};
			touch.listen(e);
		}
	}

	static inline function bit(mask:Int, index:Int):Bool
		return index >= 0 && mask & (1 << index) != 0;

	// the compositor's keymap (XKB_KEYMAP_FORMAT_TEXT_V1 in a shared file)
	static function keymap(format:Int, fd:Int, size:Int) {
		if (format != 1 || xkbContext.isNull()) {
			Posix.close(fd);
			return;
		}
		var map = WlLibc.mmap(Ptr.nil(), size, 1, 2, fd, 0); // PROT_READ, MAP_PRIVATE
		Posix.close(fd);
		if (map.toI64() == -1) return;
		var k = Xkb.xkb_keymap_new_from_string(xkbContext, map, 1, 0);
		WlLibc.munmap(map, size);
		if (k.isNull()) return;
		if (!xkbState.isNull()) Xkb.xkb_state_unref(xkbState);
		if (!xkbKeymap.isNull()) Xkb.xkb_keymap_unref(xkbKeymap);
		xkbKeymap = k;
		xkbState = Xkb.xkb_state_new(k);
		modShift = Xkb.xkb_keymap_mod_get_index(k, Mem.cstr("Shift"));
		modControl = Xkb.xkb_keymap_mod_get_index(k, Mem.cstr("Control"));
		modAlt = Xkb.xkb_keymap_mod_get_index(k, Mem.cstr("Mod1"));
		modSuper = Xkb.xkb_keymap_mod_get_index(k, Mem.cstr("Mod4"));
	}

	// a key (an XKB keycode) down or up: its KeySym unshifted (level 0, as
	// X11's XLookupKeysym 0), then its text; a repeat's again
	static function keyEvent(code:Int, down:Bool, repeat:Bool) {
		var w = keyboardIn;
		if (w == null || xkbKeymap.isNull()) return;
		var sym = Arena.scopedValue(a -> {
			var syms:Ptr<Ptr> = a.alloc(8);
			var layout = Xkb.xkb_state_key_get_layout(xkbState, code);
			var n = Xkb.xkb_keymap_key_get_syms_by_level(xkbKeymap, code, layout < 0 ? 0 : layout, 0, syms);
			n > 0 ? (syms.value : Ptr<Int32>).value : 0;
		});
		if (sym == 0) return;
		var ev = take(w, down ? KeyDown : KeyUp);
		ev.key = sym;
		ev.mods = mods;
		if (!down) {
			if (repeatKey == code) repeatKey = -1;
			return;
		}
		if (!repeat) {
			if (Xkb.xkb_keymap_key_repeats(xkbKeymap, code) != 0 && repeatRate > 0) {
				repeatKey = code;
				repeatAt = haxe.Timer.stamp() + repeatDelay / 1000;
			} else repeatKey = -1;
		}
		if (mods & (Mods.CONTROL | Mods.ALT) != 0) return;
		var text = Arena.scopedValue(a -> {
			var buf:Ptr<UInt8> = a.alloc(64);
			var n = Xkb.xkb_state_key_get_utf8(xkbState, code, buf, 64);
			if (n <= 0) "" else {
				var b = haxe.io.Bytes.alloc(n > 63 ? 63 : n);
				for (i in 0...b.length)
					b.set(i, buf[i]);
				b.toString();
			}
		});
		if (text == "") return;
		var c = StringTools.fastCodeAt(text, 0);
		if (c < 0x20 || c == 0x7F) return;
		var t = take(w, TextInput);
		t.text = text;
		t.mods = mods;
	}

	// the pointer moved in a window's content
	static function motion() {
		var w = pointerIn;
		if (w == null) return;
		var ev = take(w, MouseMove);
		ev.x = Math.round(px * w.scale());
		ev.y = Math.round(py * w.scale());
		ev.mods = mods;
	}

	// --- the data device: the clipboard, drops

	static function listenDataDevice() {
		var e = new WlDataDeviceEvents();
		e.dataOffer = id -> {
			var key = Std.string((id : Ptr).toI64());
			offerTypes.set(key, []);
			var o = new WlDataOfferEvents();
			o.offer = mime -> if (mime != null) offerTypes.get(key).push(mime);
			(id : WlDataOffer).listen(o);
		};
		e.selection = id -> {
			if (!selectionOffer.isNull() && selectionOffer != (id : WlDataOffer)) dropOffer(selectionOffer);
			selectionOffer = id;
		};
		e.enter = (serial, s, x, y, id) -> {
			dragOffer = id;
			dragWindow = find(s);
			dragSerial = serial;
			dragX = x;
			dragY = y;
			var types = id.isNull() ? null : offerTypes.get(Std.string((id : Ptr).toI64()));
			var files = types != null && types.contains("text/uri-list");
			if (!id.isNull()) {
				(id : WlDataOffer).accept(serial, files ? "text/uri-list" : null);
				if (WaylandClient.wl_proxy_get_version(id) >= 3) (id : WlDataOffer).setActions(1, 1); // (copy)
			}
		};
		e.motion = (time, x, y) -> {
			dragX = x;
			dragY = y;
		};
		e.leave = () -> {
			if (!dragOffer.isNull()) dropOffer(dragOffer);
			dragOffer = Ptr.nil();
			dragWindow = null;
		};
		e.drop = () -> {
			var w = dragWindow, o = dragOffer;
			dragOffer = Ptr.nil();
			dragWindow = null;
			if (w == null || o.isNull()) return;
			var text = receive(o, "text/uri-list");
			if (WaylandClient.wl_proxy_get_version(o) >= 3) o.finish();
			dropOffer(o);
			var files = text == null ? [] : UriList.paths(text);
			if (files.length == 0) return;
			var ev = take(w, Drop);
			ev.files = files;
			ev.x = Math.round(dragX * w.scale());
			ev.y = Math.round(dragY * w.scale());
		};
		dataDevice.listen(e);
	}

	static function dropOffer(o:WlDataOffer) {
		offerTypes.remove(Std.string((o : Ptr).toI64()));
		o.destroy();
	}

	// an offer's data of a MIME type, read whole through a pipe (null: none in 2 s)
	static function receive(o:WlDataOffer, mime:String):Null<String> {
		var fds = Arena.scopedValue(a -> {
			var p:Ptr<Int32> = a.alloc(8);
			if (Posix.pipe(p) != 0) [-1, -1] else [p[0], p[1]];
		});
		if (fds[0] < 0) return null;
		o.receive(mime, fds[1]);
		WaylandClient.wl_display_flush(display);
		Posix.close(fds[1]);
		var out = new haxe.io.BytesBuffer(), deadline = haxe.Timer.stamp() + 2;
		Arena.scoped(a -> {
			var buf:Ptr<UInt8> = a.alloc(4096);
			while (haxe.Timer.stamp() < deadline) {
				if (!readable(fds[0], 100)) continue;
				var n = Posix.read(fds[0], buf, 4096).toInt();
				if (n <= 0) break;
				for (i in 0...n)
					out.addByte(buf[i]);
			}
		});
		Posix.close(fds[0]);
		return out.getBytes().toString();
	}

	function writeClipboard(text:String) {
		if (dataManager.isNull() || dataDevice.isNull()) {
			clipboardText = text;
			return;
		}
		if (!clipboardSource.isNull()) clipboardSource.destroy();
		clipboardText = text;
		var s = dataManager.createDataSource();
		clipboardSource = s;
		var e = new WlDataSourceEvents();
		e.send = (mime, fd) -> {
			var t = clipboardText ?? "";
			var b = haxe.io.Bytes.ofString(t);
			Arena.scoped(a -> {
				var p = a.copyBytes(b);
				var at = 0;
				while (at < b.length) {
					var n = Posix.write(fd, p.add(at), b.length - at).toInt();
					if (n <= 0) break;
					at += n;
				}
			});
			Posix.close(fd);
		};
		e.cancelled = () -> {
			if (clipboardSource == s) {
				clipboardSource = Ptr.nil();
				clipboardText = null;
			}
			s.destroy();
		};
		s.listen(e);
		for (m in ["text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "TEXT", "STRING"])
			s.offer(m);
		dataDevice.setSelection(s, inputSerial);
		WaylandClient.wl_display_flush(display);
	}

	function readClipboard(callback:Null<String>->Void) {
		if (clipboardText != null && !clipboardSource.isNull()) {
			callback(clipboardText);
			return;
		}
		if (selectionOffer.isNull()) {
			callback(clipboardText);
			return;
		}
		var types = offerTypes.get(Std.string((selectionOffer : Ptr).toI64())) ?? [];
		var mime = null;
		for (m in ["text/plain;charset=utf-8", "UTF8_STRING", "text/plain", "STRING", "TEXT"])
			if (mime == null && types.contains(m)) mime = m;
		callback(mime == null ? null : receive(selectionOffer, mime));
	}

	// --- a window

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		if (display.isNull() && !connect()) throw "helder.os: no Wayland display";
		pointsW = width;
		pointsH = height;
		wlSurface = compositor.createSurface();
		var se = new WlSurfaceEvents();
		se.preferredBufferScale = factor -> {
			preferred = true;
			if (fractionalScale.isNull() && factor * 120 != scale120) rescale(factor * 120);
		};
		// (before version 6: the largest scale of the outputs it is on)
		se.enter = o -> {
			entered.push(Std.string((o : Ptr).toI64()));
			outputScale();
		};
		se.leave = o -> {
			entered.remove(Std.string((o : Ptr).toI64()));
			outputScale();
		};
		listeners.push(wlSurface.listen(se));
		if (!fractional.isNull() && !viewporter.isNull()) {
			fractionalScale = fractional.getFractionalScale(wlSurface);
			var fe = new WpFractionalScaleV1Events();
			fe.preferredScale = s -> if (s != scale120) rescale(s);
			listeners.push(fractionalScale.listen(fe));
			viewport = viewporter.getViewport(wlSurface);
		}
		xdgSurface = wmBase.getXdgSurface(wlSurface);
		var xe = new XdgSurfaceEvents();
		xe.configure = serial -> {
			xdgSurface.ackConfigure(serial);
			applyConfigure();
		};
		listeners.push(xdgSurface.listen(xe));
		toplevel = xdgSurface.getToplevel();
		var te = new XdgToplevelEvents();
		te.configure = (w, h, states) -> {
			pendingW = w;
			pendingH = h;
			pendingFullscreen = pendingMaximized = pendingActivated = false;
			// (a wl_array of uint32: size_t size, alloc; void *data)
			var size = (states : Ptr<Int64>).value.toInt(), data = (cast states.add(16) : Ptr<Ptr>).value;
			for (i in 0...Std.int(size / 4)) {
				var s = (cast data.add(4 * i) : Ptr<Int32>).value;
				if (s == 1) pendingMaximized = true else if (s == 2) pendingFullscreen = true else if (s == 4) pendingActivated = true;
			}
		};
		te.close = () -> take(this, Close);
		listeners.push(toplevel.listen(te));
		toplevel.setTitle(title);
		toplevel.setAppId(appId());
		if (!decorations.isNull()) {
			decoration = decorations.getToplevelDecoration(toplevel);
			var de = new ZxdgToplevelDecorationV1Events();
			de.configure = mode -> {
				drawsBar = mode != 2; // (server_side)
				if (configured) applyConfigure();
			};
			listeners.push(decoration.listen(de));
			decoration.setMode(2);
		}
		if (drawsBar && !subcompositor.isNull()) {
			bar = compositor.createSurface();
			barSub = subcompositor.getSubsurface(bar, wlSurface);
			barSub.setPosition(0, -BAR);
			barSub.setDesync();
		}
		wlSurface.commit();
		open.push(this);
		// (the first configure: its size, then the EGL window at the buffer's)
		var tries = 0;
		while (!configured && tries++ < 50 && WaylandClient.wl_display_roundtrip(display) >= 0) {}
		var bw = bufferW(), bh = bufferH();
		egl = WaylandEgl.wl_egl_window_create(wlSurface, bw, bh);
		surface = new Surface(Wayland, display, egl, bw, bh);
		applyScale();
		drawBar();
		WaylandClient.wl_display_flush(display);
	}

	static function appId():String {
		var p = haxe.io.Path.withoutDirectory(Sys.programPath());
		return p == "" ? "helder" : haxe.io.Path.withoutExtension(p);
	}

	inline function scale():Float
		return scale120 / 120;

	inline function bufferW():Int
		return Math.round(pointsW * scale120 / 120);

	inline function bufferH():Int
		return Math.round(pointsH * scale120 / 120);

	// the compositor's configure acknowledged: its size and states taken
	function applyConfigure() {
		var was = configured;
		configured = true;
		// (the windowed size kept while fullscreen or maximised: back to it when the compositor leaves the size to us)
		var tiled = pendingFullscreen || pendingMaximized, wasTiled = savedW > 0;
		if (tiled && !wasTiled) {
			savedW = pointsW;
			savedH = pointsH;
		}
		fullscreen = pendingFullscreen;
		maximized = pendingMaximized;
		activated = pendingActivated;
		var bar = drawsBar && !fullscreen ? BAR : 0;
		var w = pendingW > 0 ? pendingW : pointsW, h = pendingH > 0 ? pendingH - bar : pointsH;
		if (!tiled && wasTiled) {
			if (pendingW <= 0) w = savedW;
			if (pendingH <= 0) h = savedH;
			savedW = savedH = 0;
		}
		if (w < 1) w = 1;
		if (h < 1) h = 1;
		xdgSurface.setWindowGeometry(0, -bar, w, h + bar);
		var resized = w != pointsW || h != pointsH;
		pointsW = w;
		pointsH = h;
		if (was && resized) sizeChanged();
		drawBar();
	}

	// the buffer's size again (the points or the scale changed): the EGL window, the viewport, a Resize
	function sizeChanged() {
		if (surface == null) return;
		var bw = bufferW(), bh = bufferH();
		WaylandEgl.wl_egl_window_resize(egl, bw, bh, 0, 0);
		applyScale();
		if (bw != surface.width || bh != surface.height) {
			surface.resized(bw, bh);
			var ev = take(this, Resize);
			ev.x = bw;
			ev.y = bh;
		}
	}

	function applyScale() {
		if (!viewport.isNull()) viewport.setDestination(pointsW, pointsH) else if (compositorVersion >= 3) wlSurface.setBufferScale(Std.int(scale120 / 120));
	}

	function rescale(s:Int) {
		scale120 = s;
		take(this, ScaleChange);
		sizeChanged();
		barDrawn = "";
		drawBar();
	}

	// --- helder's decorations: the bar (30 points, its buttons 46 wide: minimise, maximise, close)

	static inline var BUTTON = 46;

	function barButton(x:Float):Int {
		var fromRight = pointsW - x;
		return fromRight < 0 ? -1 : fromRight < BUTTON ? 2 : fromRight < 2 * BUTTON ? 1 : fromRight < 3 * BUTTON ? 0 : -1;
	}

	function hoverBar(b:Int) {
		if (b == barHover) return;
		barHover = b;
		drawBar();
	}

	function barPress(button:Int, down:Bool, serial:Int) {
		if (button != 0x110) {
			if (button == 0x111 && down) toplevel.showWindowMenu(seat, serial, Std.int(px), Std.int(py) - BAR);
			return;
		}
		var b = barButton(px);
		if (down) {
			if (b >= 0) return;
			var now = haxe.Timer.stamp();
			if (now - lastBarPress < 0.4) {
				lastBarPress = 0;
				if (maximized) toplevel.unsetMaximized() else toplevel.setMaximized();
				return;
			}
			lastBarPress = now;
			toplevel.move(seat, serial);
			return;
		}
		switch b {
			case 0: toplevel.setMinimized();
			case 1: if (maximized) toplevel.unsetMaximized() else toplevel.setMaximized();
			case 2: take(this, Close);
			case _:
		}
	}

	// the bar drawn into a wl_shm buffer at the buffer's scale (shown unless fullscreen or the compositor's decorations)
	function drawBar() {
		if (bar.isNull() || surface == null) return;
		var show = drawsBar && !fullscreen;
		var k = Math.ceil(scale120 / 120);
		var w = pointsW * k, h = BAR * k;
		var key = '$show $w $h $barHover $activated';
		if (key == barDrawn) return;
		barDrawn = key;
		if (!barBuffer.isNull()) {
			barBuffer.destroy();
			barBuffer = Ptr.nil();
		}
		if (!show) {
			bar.attach(Ptr.nil(), 0, 0);
			bar.commit();
			return;
		}
		var stride = w * 4, size = stride * h;
		var fd = WlLibc.memfd_create(Mem.cstr("helder-bar"), 1); // MFD_CLOEXEC
		if (fd < 0 || WlLibc.ftruncate(fd, size) != 0) return;
		var px:Ptr<Int32> = cast WlLibc.mmap(Ptr.nil(), size, 3, 1, fd, 0); // PROT_READ|WRITE, MAP_SHARED
		if ((px : Ptr).toI64() == -1) {
			Posix.close(fd);
			return;
		}
		var bg = activated ? 0xFF2B2B2F : 0xFF38383D, fg = activated ? 0xFFE4E4E7 : 0xFFA1A1AA;
		for (i in 0...w * h)
			px[i] = bg;
		for (b in 0...3) {
			var x0 = w - (3 - b) * BUTTON * k;
			if (b == barHover) fill(px, w, x0, 0, BUTTON * k, h, b == 2 ? 0xFFC42B1C : 0xFF4A4A50);
			var cx = x0 + Std.int(BUTTON * k / 2), cy = Std.int(h / 2), r = 5 * k;
			switch b {
				case 0: fill(px, w, cx - r, cy, 2 * r, k, fg);
				case 1:
					fill(px, w, cx - r, cy - r, 2 * r, k, fg);
					fill(px, w, cx - r, cy + r - k, 2 * r, k, fg);
					fill(px, w, cx - r, cy - r, k, 2 * r, fg);
					fill(px, w, cx + r - k, cy - r, k, 2 * r, fg);
				case _:
					for (d in -r...r)
						for (t in 0...k) {
							dot(px, w, h, cx + d, cy + d + t, fg);
							dot(px, w, h, cx + d, cy - d - 1 + t, fg);
						}
			}
		}
		// (a line under it)
		fill(px, w, 0, h - k, w, k, 0xFF1C1C1F);
		var pool = shm.createPool(fd, size);
		barBuffer = pool.createBuffer(0, w, h, stride, 0); // (ARGB8888)
		pool.destroy();
		WlLibc.munmap(cast px, size);
		Posix.close(fd);
		if (compositorVersion >= 3) bar.setBufferScale(k);
		bar.attach(barBuffer, 0, 0);
		if (compositorVersion >= 4) bar.damageBuffer(0, 0, w, h) else bar.damage(0, 0, pointsW, BAR);
		bar.commit();
		// (the subsurface's place takes effect with the parent's commit: the next frame's swap)
	}

	static function fill(px:Ptr<Int32>, stride:Int, x:Int, y:Int, w:Int, h:Int, c:Int)
		for (j in y...y + h)
			for (i in x...x + w)
				if (i >= 0 && i < stride && j >= 0) px[j * stride + i] = c;

	static inline function dot(px:Ptr<Int32>, stride:Int, h:Int, x:Int, y:Int, c:Int)
		if (x >= 0 && x < stride && y >= 0 && y < h) px[y * stride + x] = c;

	// --- Window's calls

	function destroy() {
		open.remove(this);
		if (pointerIn == this) pointerIn = null;
		if (keyboardIn == this) keyboardIn = null;
		for (l in listeners)
			Proxy.forget(l);
		if (!barBuffer.isNull()) barBuffer.destroy();
		if (!barSub.isNull()) barSub.destroy();
		if (!bar.isNull()) bar.destroy();
		if (!decoration.isNull()) decoration.destroy();
		if (!viewport.isNull()) viewport.destroy();
		if (!fractionalScale.isNull()) fractionalScale.destroy();
		if (!egl.isNull()) WaylandEgl.wl_egl_window_destroy(egl);
		toplevel.destroy();
		xdgSurface.destroy();
		wlSurface.destroy();
		WaylandClient.wl_display_flush(display);
	}

	function setTitle(t:String) {
		toplevel.setTitle(t);
		WaylandClient.wl_display_flush(display);
	}

	// (a size in pixels asked: the compositor may configure another)
	function resize(w:Int, h:Int) {
		pointsW = Math.round(w * 120 / scale120);
		pointsH = Math.round(h * 120 / scale120);
		var bar = drawsBar && !fullscreen ? BAR : 0;
		xdgSurface.setWindowGeometry(0, -bar, pointsW, pointsH + bar);
		sizeChanged();
		drawBar();
		WaylandClient.wl_display_flush(display);
	}

	function setMinSize(w:Int, h:Int) {
		minW = w;
		minH = h;
		toplevel.setMinSize(w, h + (drawsBar ? BAR : 0));
		WaylandClient.wl_display_flush(display);
	}

	function setFullscreen(on:Bool) {
		if (on) toplevel.setFullscreen(Ptr.nil()) else toplevel.unsetFullscreen();
		// (asked: shown as asked until the compositor configures otherwise)
		pendingFullscreen = on;
		fullscreen = on;
		WaylandClient.wl_display_flush(display);
	}

	function raise() {}

	// (no global coordinates on Wayland)
	function position():Null<{x:Int, y:Int}>
		return null;

	function moveTo(x:Int, y:Int) {}

	function setCursor(c:Cursor) {
		cursorNow = c;
		if (pointerIn == this && !pointerOnBar) applyCursor(pointerSerial);
	}

	// cursor-shape-v1's shape, else the theme's image on a surface of ours
	static function applyCursor(serial:Int) {
		var c = pointerOnBar ? Cursor.Default : cursorNow;
		var i:Int = c;
		if (!cursorDevice.isNull()) {
			// (default 1, pointer 4, text 9, crosshair 8, move 13, not_allowed 15, ew_resize 26, ns_resize 27, grab 16, grabbing 17)
			cursorDevice.setShape(serial, [1, 4, 9, 8, 13, 15, 26, 27, 16, 17][i]);
			return;
		}
		if (cursorTheme.isNull()) {
			if (WaylandCursor.load("libwayland-cursor.so.0") != null) return;
			var size = Std.parseInt(Sys.getEnv("XCURSOR_SIZE") ?? "") ?? 24;
			cursorTheme = Arena.scopedValue(a -> WaylandCursor.wl_cursor_theme_load(Sys.getEnv("XCURSOR_THEME") == null ? Ptr.nil() : a.cstring(Sys.getEnv("XCURSOR_THEME")),
				size, shm));
			if (cursorTheme.isNull()) return;
			cursorSurface = compositor.createSurface();
		}
		var name = ["left_ptr", "hand2", "xterm", "crosshair", "fleur", "not-allowed", "sb_h_double_arrow", "sb_v_double_arrow", "hand1", "grabbing"][i];
		var cur = Arena.scopedValue(a -> WaylandCursor.wl_cursor_theme_get_cursor(cursorTheme, a.cstring(name)));
		if (cur.isNull()) cur = WaylandCursor.wl_cursor_theme_get_cursor(cursorTheme, Mem.cstr("left_ptr"));
		if (cur.isNull()) return;
		// (struct wl_cursor { unsigned image_count; struct wl_cursor_image **images; char *name; })
		var image = ((cast cur.add(8) : Ptr<Ptr>).value : Ptr<Ptr>).value;
		var im:Ptr<Int32> = cast image;
		var buffer:WlBuffer = WaylandCursor.wl_cursor_image_get_buffer(image);
		if (buffer.isNull()) return;
		pointer.setCursor(serial, cursorSurface, im[2], im[3]);
		cursorSurface.attach(buffer, 0, 0);
		cursorSurface.damage(0, 0, im[0], im[1]);
		cursorSurface.commit();
	}

	// --- the loop

	static function find(s:Ptr):Null<WaylandWindow> {
		for (w in open)
			if ((w.wlSurface : Ptr) == s) return w;
		return null;
	}

	static function barOf(s:Ptr):Null<WaylandWindow> {
		for (w in open)
			if (!w.bar.isNull() && (w.bar : Ptr) == s) return w;
		return null;
	}

	static function byWindow(win:Null<Window>):Null<WaylandWindow> {
		for (w in open)
			if (w.owner == win) return w;
		return null;
	}

	// an event of the queue's for w
	static function take(w:WaylandWindow, kind:EventKind):Event {
		var e = pool.length > 0 ? pool.pop() : new Event();
		e.kind = kind;
		e.window = w.owner;
		e.key = 0;
		e.x = e.y = 0;
		e.button = 0;
		e.deltaX = e.deltaY = 0;
		e.mods = 0;
		e.text = "";
		e.pointer = null;
		e.files = [];
		queue.push(e);
		return e;
	}

	// reads what the connection has, dispatches it, then the queue's events to onEvent
	static function poll(onEvent:Event->Void) {
		if (display.isNull()) return;
		read(0);
		// (a key held: its repeats due)
		if (repeatKey >= 0 && keyboardIn != null) {
			var now = haxe.Timer.stamp();
			while (repeatKey >= 0 && now >= repeatAt) {
				keyEvent(repeatKey, true, true);
				repeatAt += 1 / repeatRate;
				if (now - repeatAt > 0.5) repeatAt = now + 1 / repeatRate;
			}
		}
		while (queue.length > 0) {
			var e = queue.shift();
			onEvent(e);
			pool.push(e);
		}
		WaylandClient.wl_display_flush(display);
	}

	// the socket read (waiting up to ms; 0: what is there) and dispatched
	static function read(ms:Int) {
		while (WaylandClient.wl_display_prepare_read(display) != 0)
			WaylandClient.wl_display_dispatch_pending(display);
		WaylandClient.wl_display_flush(display);
		var ready = readable(WaylandClient.wl_display_get_fd(display), ms);
		if (ready) WaylandClient.wl_display_read_events(display) else WaylandClient.wl_display_cancel_read(display);
		WaylandClient.wl_display_dispatch_pending(display);
		if (WaylandClient.wl_display_get_error(display) != 0 && open.length > 0) {
			// (the connection broke: every window asked to close)
			for (w in open)
				take(w, Close);
		}
	}

	// (fd readable within ms: -1 forever, 0 now; in a safe region, as ppoll waits)
	public static function readable(fd:Int, ms:Int):Bool
		return Arena.scopedValue(a -> {
			var pfd:Ptr<Int32> = cast a.alloc(8);
			pfd[0] = fd;
			pfd[1] = 1; // POLLIN
			var ts:Ptr<Int64> = cast a.alloc(16);
			ts[0] = Std.int(ms / 1000);
			ts[1] = (ms % 1000) * 1000000;
			WlLibc.ppoll(pfd, 1, ms < 0 ? Ptr.nil() : ts, Ptr.nil()) > 0;
		});

	// waits for the connection to have events, or seconds (a key's repeat sooner)
	static function waitFor(seconds:Float) {
		if (display.isNull()) return;
		WaylandClient.wl_display_flush(display);
		if (queue.length > 0) return;
		if (repeatKey >= 0) seconds = Math.min(seconds < 0 ? 1e6 : seconds, Math.max(0, repeatAt - haxe.Timer.stamp()));
		var loop = helder.async.Driven.MainLoop.main;
		if (loop != null) {
			loop.wait(seconds, WaylandClient.wl_display_get_fd(display));
			return;
		}
		read(seconds < 0 ? -1 : Std.int(seconds * 1000));
	}
}
