import hxmc.os.android.MainThread;
import hxmc.ui.*;
import hxmc.ui.native.*;
import hxmc.ui.native.android.AndroidBackend;
import hxmc.view.*;

// hxmc.ui.native on Android (CI's android job, an x86-64 emulator:
// packages/ui/test/android-native.sh reads what it prints from logcat):
// the native form (examples/NativeForm.hx) in a NativeHost of
// android.widget's views, its steps on the main thread's frames; checked
// there as NativeTest checks the desktop's (made, measured by the views,
// placed where the layout put them, driven by the views' own calls with the
// signals following, and the other way); then the form reset and left to
// the script's real input (adb: taps, text through the input method),
// whose effects are logged as they come; once the field holds "Linus",
// the box is checked and Submit was pressed, a few seconds for the
// screenshot and the window closes.
//   haxe -lib hxmc.ui -cp packages/ui/examples -cp packages/ui/test -main AndroidNativeTest
//     --custom-target hxmc=AndroidNativeTest.apk -D hxmc.target=android-x86_64 -D hxmc.android-package=org.hxmc.nativetest
class AndroidNativeTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) failed++;
		Sys.println('AndroidNativeTest: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : " (" + detail + ")"));
	}

	static inline function on(f:Void->Void)
		MainThread.run(f);

	// the program's thread waits (the main thread's frames go on)
	static function settle(seconds = 0.4) {
		var t = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t < seconds)
			MainThread.wait(0.05);
	}

	static function main() {
		Sys.println("AndroidNativeTest: start");
		var backend = new AndroidBackend();
		var driver:NativeDriver = backend;
		var host = new NativeHost("AndroidNativeTest", 0, 0, backend);
		var app = new NativeForm();
		Render.render(app.view(), host.root);
		AndroidBackend.start(host);
		// (the first steps make the views: up to 10 s)
		var made = false, t0 = haxe.Timer.stamp(), frames = 0;
		on(() -> {
			var f = MainThread.onFrame;
			MainThread.onFrame = () -> {
				frames++;
				f();
			};
		});
		while (!made && haxe.Timer.stamp() - t0 < 10) {
			settle(0.25);
			on(() -> made = (cast host.root.find("submit") : Control).handle != 0);
		}
		settle(0.5);
		if (!made) {
			check("the widgets made", false, frames + " frames");
			on(() -> host.close());
			return;
		}
		var field:Control = null, agree:Control = null, volume:Control = null, submit:Control = null, count:Control = null, greeting:TextNode = null;
		on(() -> {
			field = cast host.root.find("name");
			agree = cast host.root.find("agree");
			volume = cast host.root.find("volume");
			submit = cast host.root.find("submit");
			count = cast host.root.find("count");
			greeting = cast host.root.find("greeting");
			Sys.println('AndroidNativeTest: window ${backend.windowWidth()}x${backend.windowHeight()} dp');
			check("the widgets made", field.handle != 0 && agree.handle != 0 && volume.handle != 0 && submit.handle != 0);
			check("measured by the views", submit.width > 30 && submit.height > 20 && field.height > 20, '${submit.width}x${submit.height}, field ${field.height}');
			check("a label for text", greeting.height > 10 && greeting.width > 40, '${greeting.width}x${greeting.height}');
			check("the button disabled until agreed", !submit.enabled);
		});
		// (the views' positions, once Android laid them out: within a dp of the layout's)
		function near(a:Array<Int>, x:Float, y:Float, w:Float, h:Float)
			return a.length == 4 && Math.abs(a[0] - x) <= 1 && Math.abs(a[1] - y) <= 1 && Math.abs(a[2] - w) <= 1 && Math.abs(a[3] - h) <= 1;
		on(() -> for (c in [field, agree, submit, count]) {
			var a = driver.allocation(c.handle);
			check("placed: " + c.tag, near(a, c.absX, c.absY, c.width, c.height), a.join(",") + " for " + [c.absX, c.absY, c.width, c.height].join(","));
		});
		// the views' own calls
		on(() -> driver.type(field.handle, "Ada"));
		settle();
		on(() -> check("typed text reaches the signal", app.name.value == "Ada" && greeting.text == "Hello, Ada!", app.name.value));
		on(() -> driver.toggle(agree.handle, true));
		settle();
		on(() -> check("a toggle", app.agree.value && submit.enabled));
		on(() -> {
			driver.click(submit.handle);
			driver.click(submit.handle);
		});
		settle();
		on(() -> check("clicks", app.submitted.value == 2 && count.text == "Submitted 2 times", count.text));
		on(() -> driver.slide(volume.handle, 0.75));
		settle();
		on(() -> {
			var shown:TextNode = cast host.root.find("volume-shown");
			check("a slider", Math.abs(app.volume.value - 0.75) < 0.002 && shown.text == "75%", '${app.volume.value} ${shown.text}');
			// the other way: signals to the views
			app.name.value = "Grace";
			app.volume.value = 0.5;
		});
		settle();
		on(() -> {
			check("a signal sets the field", driver.fieldText(field.handle) == "Grace", driver.fieldText(field.handle));
			check("and the slider", Math.abs(driver.sliderValue(volume.handle) - 0.5) < 0.002, '${driver.sliderValue(volume.handle)}');
		});
		// a longer button label: measured again, the row laid out again
		var before = 0.0;
		on(() -> {
			before = count.width;
			app.submitted.value = 1000;
		});
		settle();
		on(() -> {
			var a = driver.allocation(count.handle);
			check("a new label measured again", count.width > before && near(a, count.absX, count.absY, count.width, count.height),
				'$before -> ${count.width}, allocated $a');
			// the real input next (android-native.sh): from a clean form
			app.name.value = "";
			app.agree.value = false;
			app.submitted.value = 0;
		});
		settle();
		Sys.println("AndroidNativeTest: ready for input");
		// what the user does, logged as it changes; done once all three came
		var last = "", done = false;
		t0 = haxe.Timer.stamp();
		while (!done && haxe.Timer.stamp() - t0 < 120 && !host.closed) {
			on(() -> {
				var now = 'name "${app.name.value}", agree ${app.agree.value}, submitted ${app.submitted.value}, greeting "${greeting.text}"';
				if (now != last) Sys.println("AndroidNativeTest: input: " + now);
				last = now;
				done = app.name.value == "Linus" && app.agree.value && app.submitted.value >= 1 && greeting.text == "Hello, Linus!";
			});
			settle(0.2);
		}
		check("the user's input (taps, text through the input method)", done, last);
		Sys.println("AndroidNativeTest: input done");
		settle(4);
		Sys.println('AndroidNativeTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		on(() -> host.close());
		Sys.println("AndroidNativeTest: done");
	}
}
