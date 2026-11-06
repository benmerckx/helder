package helder.ui;

import helder.test.Test;
import helder.ui.platform.*;
import helder.ui.widgets.TextField;
import helder.ui.widgets.TextArea;

// Ui.policy's defaults (the test lane: natively, a desktop; as wasm32-wasi,
// a browser's): on the desktop text fields and areas drawn even where the
// window has the platform's editors, the menus native; in the browser and
// on phones the platform's editor; host="native" on a node, or the policy,
// asks for the platform's editor on the desktop still.
private class Views implements PlatformViews {
	public var made = 0;

	public function new() {}

	public function editor(multiline:Bool):Null<PlatformEditor> {
		made++;
		return null;
	}

	public function poll() {}

	public function menu(items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool
		return false;

	public function menuBar(menus:Array<PlatformMenuItem>, chosen:Int->Void):Bool
		return false;
}

function tests() {
	describe("Ui.policy", () -> {
		test("the defaults: drawn text on the desktop, the platform's elsewhere", () -> {
			var ui = new Ui(new helder.ui.draw.DrawText(), 200, 100);
			ui.platform = new Views();
			var f = new TextField("hi"), a = new TextArea("");
			ui.root.append(f);
			ui.root.append(a);
			var desktop = Ui.desktop();
			#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
			equals(desktop, hxmc.unsafe.Mem.platform() == 0 && hxmc.unsafe.Mem.target() < 9);
			#else
			equals(desktop, false);
			#end
			equals(ui.hostOf(f, "text-field"), desktop ? Drawn : Native);
			equals(ui.hostOf(a, "text-area"), desktop ? Drawn : Native);
			equals(ui.hostOf(f, "context-menu"), Native);
			equals(ui.hostOf(f, "menubar"), Native);
		});
		test("native asked for: on a node, or by the policy", () -> {
			var ui = new Ui(new helder.ui.draw.DrawText(), 200, 100);
			var views = new Views();
			ui.platform = views;
			var f = new TextField("hi"), g = new TextField("ho");
			f.host = Native;
			ui.root.append(f);
			ui.root.append(g);
			equals(ui.hostOf(f, "text-field"), Native);
			ui.policy["text-field"] = Host.Native;
			equals(ui.hostOf(g, "text-field"), Native);
			ui.policy["text-field"] = Host.Drawn;
			equals(ui.hostOf(g, "text-field"), Drawn);
			// (no platform's views: drawn whatever is asked)
			ui.platform = null;
			equals(ui.hostOf(f, "text-field"), Drawn);
		});
	});
}
