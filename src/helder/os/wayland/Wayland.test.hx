package helder.os.wayland;

import helder.test.Test;

// The generated Wayland bindings without a compositor (Linux, natively):
// the wl_interface and wl_message structs Interfaces makes (names,
// versions, counts, signatures, the arguments' interfaces), requests
// marshalled into wl_argument slots (Proxy.recorder in libwayland's place:
// ints, a fixed, strings, objects, a new_id's interface, wl_registry.bind's
// "usun", a destructor's flag), events decoded from slots back to the
// handlers (ints, a negative fixed, a string, an object); the scanner's
// signatures for a protocol of its own.
@:hxmc.unsafe(gc) function tests() {
	describe("Wayland bindings", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		// (Linux's alone: a constant condition, the others' builds without it)
		if (hxmc.Platform.os() == 0 && hxmc.Platform.target() < 9) {
		var seen:Array<{opcode:Int, iface:String, version:Int, flags:Int, args:Array<String>}> = [];
		function record(sigs:String) {
			Proxy.recorder = (proxy, opcode, iface, version, flags, args, count) -> {
				var a = [];
				for (k in 0...count) {
					var c = sigs.charAt(k);
					a.push(c == "s" ? Proxy.string(args, k) ?? "null" : Std.string(Proxy.int(args, k)));
				}
				seen.push({opcode: opcode, iface: iface.isNull() ? "" : Interfaces.name(iface), version: version, flags: flags, args: a});
				return hxmc.unsafe.Ptr.ofI64(0x1000);
			};
		}
		afterEach(() -> {
			Proxy.recorder = null;
			seen.resize(0);
		});
		test("the interface structs: names, versions, messages, their interfaces", () -> {
			var s = Interfaces.get("wl_surface");
			equals(Interfaces.name(s), "wl_surface");
			equals(Interfaces.version(s), 6);
			equals(Interfaces.count(s, false), 11);
			equals(Interfaces.count(s, true), 4);
			equals(Interfaces.message(s, false, 1), {name: "attach", signature: "?oii", types: ["wl_buffer", null, null]});
			equals(Interfaces.message(s, false, 3), {name: "frame", signature: "n", types: ["wl_callback"]});
			equals(Interfaces.message(s, true, 2), {name: "preferred_buffer_scale", signature: "6i", types: [null]});
			var t = Interfaces.get("xdg_toplevel");
			equals(Interfaces.message(t, false, 4), {name: "show_window_menu", signature: "ouii", types: ["wl_seat", null, null, null]});
			equals(Interfaces.message(Interfaces.get("wl_registry"), false, 0), {name: "bind", signature: "usun", types: [null, null, null, null]});
			// (the same struct each time: libwayland compares them by name, helder by address)
			equals(Interfaces.get("wl_surface").toI64(), s.toI64());
			assert(Interfaces.get("no_such_interface").isNull());
		});
		test("requests: ints, strings, objects, a new_id, bind, a destructor", () -> {
			var surface:helder.os.wayland.protocol.WaylandProtocol.WlSurface = hxmc.unsafe.Ptr.ofI64(0x2000);
			record("oii");
			surface.attach(hxmc.unsafe.Ptr.ofI64(0x3000), 3, -4);
			equals(seen[0].opcode, 1);
			equals(seen[0].args, [Std.string(0x3000), "3", "-4"]);
			record("n");
			var cb = surface.frame();
			equals(seen[1].iface, "wl_callback");
			equals((cb : hxmc.unsafe.Ptr).toI64(), hxmc.unsafe.Ptr.ofI64(0x1000).toI64());
			record("s");
			var top:helder.os.wayland.protocol.XdgShellProtocol.XdgToplevel = hxmc.unsafe.Ptr.ofI64(0x4000);
			top.setTitle("Fenêtre ✓");
			equals(seen[2].args, ["Fenêtre ✓"]);
			record("usun");
			var reg:helder.os.wayland.protocol.WaylandProtocol.WlRegistry = hxmc.unsafe.Ptr.ofI64(0x5000);
			reg.bind(7, Interfaces.get("wl_compositor"), 5);
			equals(seen[3].args, ["7", "wl_compositor", "5", "0"]);
			equals(seen[3].version, 5);
			equals(seen[3].iface, "wl_compositor");
			record("");
			surface.destroy();
			equals(seen[4].flags, 1);
			record("ff");
			var viewport:helder.os.wayland.protocol.ViewporterProtocol.WpViewport = hxmc.unsafe.Ptr.ofI64(0x6000);
			viewport.setSource(1.5, -2.25, 100, 50);
			equals(seen[5].args.slice(0, 2), [Std.string(Std.int(1.5 * 256)), Std.string(Std.int(-2.25 * 256))]);
		});
		test("events: decoded from the slots to the handlers", () -> {
			Proxy.recorder = (_, _, _, _, _, _, _) -> hxmc.unsafe.Ptr.nil();
			var got = [];
			var e = new helder.os.wayland.protocol.WaylandProtocol.WlPointerEvents();
			e.motion = (time, x, y) -> got.push('motion $time $x $y');
			e.button = (serial, time, button, state) -> got.push('button $serial $button $state');
			var p:helder.os.wayland.protocol.WaylandProtocol.WlPointer = hxmc.unsafe.Ptr.ofI64(0x7000);
			var slot = p.listen(e);
			hxmc.unsafe.Arena.scoped(a -> {
				var args:hxmc.unsafe.Ptr<hxmc.unsafe.Int64> = cast a.alloc(32);
				args[0] = 99;
				args[1] = Std.int(12.5 * 256);
				args[2] = -Std.int(3.25 * 256);
				Proxy.deliver(slot, 2, args);
				args[0] = 5;
				args[1] = 1000;
				args[2] = 0x110;
				args[3] = 1;
				Proxy.deliver(slot, 3, args);
				var r = new helder.os.wayland.protocol.WaylandProtocol.WlRegistryEvents();
				r.global = (name, iface, version) -> got.push('global $name $iface $version');
				var reg:helder.os.wayland.protocol.WaylandProtocol.WlRegistry = hxmc.unsafe.Ptr.ofI64(0x8000);
				var rs = reg.listen(r);
				args[0] = 3;
				Proxy.setString(a, args, 1, "xdg_wm_base");
				args[2] = 6;
				Proxy.deliver(rs, 0, args);
				Proxy.forget(rs);
			});
			Proxy.forget(slot);
			equals(got, ["motion 99 12.5 -3.25", "button 5 272 1", "global 3 xdg_wm_base 6"]);
		});
		}
		#end
		test("the scanner: a protocol's signatures and module", () -> {
			var xml = Xml.parse('<protocol name="test_proto"><interface name="test_thing" version="3">
				<request name="make"><arg name="id" type="new_id" interface="test_thing"/><arg name="label" type="string" allow-null="true"/></request>
				<request name="destroy" type="destructor"/>
				<event name="moved" since="2"><arg name="x" type="fixed"/><arg name="fd" type="fd"/></event>
				<enum name="kind"><entry name="a" value="0"/><entry name="2d" value="1"/></enum>
			</interface></protocol>').firstElement();
			var r = Scanner.generate(xml, "test.xml");
			equals(r.module, "TestProtoProtocol");
			assert(r.code.indexOf('{name: "make", signature: "n?s", types: ["test_thing", null]}') >= 0, "make's message");
			assert(r.code.indexOf('{name: "moved", signature: "2fh", types: [null, null]}') >= 0, "moved's message");
			assert(r.code.indexOf("public inline function make(label:Null<String>):TestThing") >= 0, "make's request");
			assert(r.code.indexOf("Proxy.marshal(this, 1, Ptr.nil(), -1, 1, args, 0)") >= 0, "destroy's flag");
			assert(r.code.indexOf("var _2d = 1;") >= 0, "an entry starting with a digit");
		});
	});
}
