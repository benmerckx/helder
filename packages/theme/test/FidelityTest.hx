import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.theme.Shadcn;
import hxmc.ui.*;
import hxmc.ui.draw.*;
import hxmc.ui.widgets.Widgets.*;
import hxmc.view.*;

// hxmc's widgets under Shadcn.sheet against shadcn/ui's own markup and CSS
// drawn by Chromium (ref/*.png, ref.mjs; make theme-fidelity-check): each
// case of ref/cases.json (a component, its variant, size, state, light or
// dark) drawn headless in its frame (padding 16, Inter), hovered by the
// pointer or focused by Tab as the case asks, then compared as BoxTest
// compares: a small mean difference, few pixels far apart (edges and
// glyphs are anti-aliased differently). Prints each case's numbers;
// writes each drawing to <out dir>.
//   FidelityTest <ref dir> <out dir>
class FidelityTest implements Markup {
	// (the page's width in ref.mjs: md: holds)
	static inline var W = 800;
	static inline var H = 600;
	static inline var MEAN = 4.0;
	static inline var FAR = 96;
	static inline var MAX_FAR = 0.02;

	// the cases known to differ, by the start of their names, and why (what
	// hxmc.ui lacks yet): reported, not failed; one that agrees is reported too
	static final KNOWN = [
		"button-focus" => "ui's own focus ring drawn over the theme's",
		"button-outline-focus" => "ui's own focus ring drawn over the theme's",
		"button-invalid-focus" => "ui's own focus ring drawn over the theme's",
		"input-focus" => "ui's own focus ring drawn over the theme's",
		"checkbox-focus" => "ui's own focus ring drawn over the theme's",
		"badge-default" => "rounded-full's radius not reduced as CSS reduces it (an ellipse, not a pill)",
		"badge-destructive" => "rounded-full's radius not reduced as CSS reduces it (an ellipse, not a pill)",
		"input-value" => "md: (window at least 48rem wide) does not hold: text-base, not md:text-sm",
		"input-invalid" => "md: (window at least 48rem wide) does not hold: text-base, not md:text-sm",
		"switch-" => "Switch has no size (data-size): its data-[size=…] rules, its width and height, never apply",
		"textarea-" => "md: does not hold (text-base, not md:text-sm), and its rows give it more height than min-h-16 with field-sizing-content",
		"radio-group-" => "a <button>'s content is centred vertically by the browser; the item's indicator, at its top here, is not",
		"progress-" => "the indicator is not moved by translateX(-(100 - value)%) as shadcn's, and the widget's own width (160) wins over w-full",
	];

	static function known(name:String):Null<String> {
		for (k => why in KNOWN)
			if (StringTools.startsWith(name, k)) return why;
		return null;
	}

	// (null: no widget for the component yet, or for this case, which is skipped;
	// the case's attributes are set on the component's node after)
	static function widget(c:Dynamic):Null<View> {
		var text:String = c.text, variant:String = c.variant ?? "default", size:String = c.size ?? "default";
		return switch (c.component : String) {
			case "button": <Button label={text} variant={variant} size={size}/>;
			case "badge": <Badge label={text} variant={variant}/>;
			case "toggle": <Toggle pressed={new Signal(c.on == true)} label={text} variant={variant} size={size}/>;
			case "input": <Input value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "checkbox": <Checkbox checked={new Signal(c.checked == true)}/>;
			case "switch": <Switch checked={new Signal(c.checked == true)} size={size}/>;
			case "label" if (c.peerDisabled != true): <Label text={text}/>;
			case "textarea": <Textarea value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "progress": <Progress value={(c.value : Float) / 100}/>;
			case "radio-group": <RadioGroup value={new Signal("Default")} options={["Default", "Comfortable"]}/>;
			case "alert": <Alert variant={variant}><AlertTitle text={c.title}/><AlertDescription text={text}/></Alert>;
			case "card":
				<Card>
					<CardHeader>
						<CardTitle text={c.title}/>
						<CardDescription text={c.description}/>
						<CardAction><Button variant="link" label={c.action}/></CardAction>
					</CardHeader>
					<CardContent><text>{text}</text></CardContent>
					<CardFooter><Button label={c.footer}/></CardFooter>
				</Card>;
			case _: null;
		}
	}

	static function find(n:Node, slot:String):Null<Node> {
		if (n.slot == slot) return n;
		for (k in n.children) {
			var f = find(k, slot);
			if (f != null) return f;
		}
		return null;
	}

	static function main() {
		var args = Sys.args();
		var cases:Array<Dynamic> = haxe.Json.parse(sys.io.File.getContent(args[0] + "/cases.json"));
		var device = Device.create(Surface.headless(W, H));
		var r = new Renderer(device);
		var failed = 0, skipped = 0;
		for (c in cases) {
			var view = widget(c);
			if (view == null) {
				skipped++;
				continue;
			}
			var w:Int = c.w, h:Int = c.h;
			var ui = new Ui(new DrawText(), W, H);
			ui.theme = Shadcn.sheet;
			ui.dark = c.dark == true;
			var frame = new Node("frame");
			frame.slot = "body";
			frame.style.set({width: w, height: h, padding: 16, fontFamily: "Inter", direction: c.block ? Column : Row, alignItems: c.block ? Stretch : Start});
			ui.root.append(frame);
			Render.render(view, frame);
			ui.update();
			var states:Array<String> = c.states == null ? [] : c.states;
			var target = find(ui.root, c.component);
			var attrs:haxe.DynamicAccess<Dynamic> = c.attrs ?? {};
			for (k => v in attrs)
				target.setAttr(k, v == true ? "" : v);
			ui.update();
			if (states.contains("hover")) ui.pointerMove(target.absX + target.width / 2, target.absY + target.height / 2);
			if (states.contains("focus-visible")) {
				ui.keyDown(Key.TAB, 0);
				ui.keyUp(Key.TAB, 0);
			}
			ui.update();
			var pixels = Bytes.alloc(W * H * 4);
			var enc = device.beginFrame();
			var pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 0, 1)}]};
			enc.beginPass(pass);
			r.begin(W, H);
			ui.paint(r);
			r.end(enc);
			enc.endPass();
			device.readPixels(pixels);
			device.endFrame();
			var got = Bytes.alloc(w * h * 4);
			for (y in 0...h)
				got.blit(y * w * 4, pixels, y * W * 4, w * 4);
			sys.io.File.saveBytes('${args[1]}/${c.name}.png', Png.encode(got, w, h));
			var want = PngDecoder.decode(sys.io.File.getBytes('${args[0]}/${c.name}.png'));
			var total = 0.0, far = 0;
			for (i in 0...w * h) {
				var d = 0;
				for (k in 0...3) {
					var v = Std.int(Math.abs(got.get(4 * i + k) - want.rgba.get(4 * i + k)));
					if (v > d) d = v;
				}
				total += d;
				if (d > FAR) far++;
			}
			var mean = total / (w * h);
			var ok = mean < MEAN && far <= MAX_FAR * w * h, why = known(c.name);
			if (!ok && why == null) failed++;
			var verdict = why == null ? (ok ? "ok" : "FAILED") : ok ? 'ok, though known to differ ($why)' : 'differs, as known ($why)';
			Sys.println('FidelityTest: ${c.name} $verdict (mean ${Math.round(mean * 100) / 100}, $far pixels off by more than $FAR)');
		}
		device.dispose();
		Sys.println('FidelityTest: ${cases.length - skipped} cases ($skipped without a widget yet)' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
