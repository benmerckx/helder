import hxmc.ui.*;
import hxmc.ui.native.*;
import hxmc.ui.reactive.*;
import hxmc.unsafe.*;

// hxmc.ui.native on the platform's backend (make ui-draw-check: GTK 3 under
// Xvfb; Win32 and AppKit in CI): the native form (examples/NativeForm.hx) rendered into
// a NativeHost; its controls' widgets made, measured by the platform, placed
// where the layout put them (the platform's positions and sizes checked),
// driven by the platform's own calls (NativeDriver: a click, text typed, a
// toggle, a value) with the signals following, and the other way; then a
// screenshot (out.png, where the platform can) and the window closed.
//   NativeTest [out.png]
class NativeTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('NativeTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var out = Sys.args()[0];
		var backend:NativeBackend = if (Mem.os() == 2) new hxmc.ui.native.win32.Win32Backend() else if (Mem.os() == 1) new hxmc.ui.native.appkit.AppKitBackend() else
			new hxmc.ui.native.gtk.GtkBackend();
		var driver:NativeDriver = cast backend;
		var host = new NativeHost("NativeTest", 440, 380, backend);
		var app = new NativeForm();
		Render.render(app.view(), host.root);
		// (GTK allocates on its frame clock: a few frames of real time)
		function settle() {
			var t = haxe.Timer.stamp();
			while (haxe.Timer.stamp() - t < 0.15) {
				backend.pump(false);
				host.step();
				Sys.sleep(0.005);
			}
		}
		settle();
		function find(tag:String):Node {
			var n = host.root.find(tag);
			if (n == null) throw "NativeTest: no " + tag;
			return n;
		}
		var field:Control = cast find("name"), agree:Control = cast find("agree"), volume:Control = cast find("volume");
		var submit:Control = cast find("submit"), count:Control = cast find("count");
		check("the widgets made", field.handle != 0 && agree.handle != 0 && volume.handle != 0 && submit.handle != 0);
		check("measured by GTK", submit.width > 30 && submit.height > 20 && field.height > 20, '${submit.width}x${submit.height}, field ${field.height}');
		// (GTK's allocation: where the layout placed it)
		for (c in [field, agree, submit, count]) {
			var a = driver.allocation(c.handle);
			check("placed: " + c.tag, a[0] == Math.round(c.absX) && a[1] == Math.round(c.absY), a.join(",") + " for " + c.absX + "," + c.absY);
		}
		var greeting:TextNode = cast find("greeting");
		check("a label for text", greeting.height > 10 && greeting.width > 40, '${greeting.width}x${greeting.height}');
		check("the button disabled until agreed", !submit.enabled);
		// GTK's own calls
		driver.type(field.handle, "Ada");
		settle();
		check("typed text reaches the signal", app.name.value == "Ada" && greeting.text == "Hello, Ada!", app.name.value);
		driver.toggle(agree.handle, true);
		settle();
		check("a toggle", app.agree.value && submit.enabled);
		driver.click(submit.handle);
		driver.click(submit.handle);
		settle();
		check("clicks", app.submitted.value == 2 && count.text == "Submitted 2 times", count.text);
		driver.slide(volume.handle, 0.75);
		settle();
		var shown:TextNode = cast find("volume-shown");
		check("a slider", Math.abs(app.volume.value - 0.75) < 0.002 && shown.text == "75%", '${app.volume.value} ${shown.text}');
		// the other way: signals to widgets
		app.name.value = "Grace";
		app.volume.value = 0.5;
		settle();
		var entryText = driver.fieldText(field.handle);
		check("a signal sets the entry", entryText == "Grace", entryText);
		check("and the slider", Math.abs(driver.sliderValue(volume.handle) - 0.5) < 0.002, '${driver.sliderValue(volume.handle)}');
		// a longer button label: measured again, the row laid out again
		var before = count.width;
		app.submitted.value = 1000;
		settle();
		check("a new label measured again", count.width > before && driver.allocation(count.handle)[2] >= Math.round(count.width) - 1,
			'$before -> ${count.width}, allocated ${driver.allocation(count.handle)}');
		// (sizes too: measured again when a state changed it, a disabled button's)
		for (c in [submit, count, agree, field]) {
			var a = driver.allocation(c.handle);
			check("allocated as laid out: " + c.tag, a[2] == Math.round(c.width) && a[3] == Math.round(c.height), a.join(",") + " for " + c.width + "x" + c.height);
		}
		if (out != null && !driver.screenshot(out)) Sys.println("NativeTest: (no screenshot on this platform)");
		host.close();
		check("closed", host.closed && !backend.pump(false));
		Sys.println('NativeTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
