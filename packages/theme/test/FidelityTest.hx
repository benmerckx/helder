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
	static inline var H = 300;
	static inline var MEAN = 4.0;
	static inline var FAR = 96;
	static inline var MAX_FAR = 0.02;

	static function widget(c:Dynamic):View {
		var attrs:Dynamic = c.attrs ?? {};
		var disabled = Reflect.hasField(attrs, "disabled"), invalid = Reflect.field(attrs, "aria-invalid") == "true";
		return switch (c.component : String) {
			case "button": <Button variant={c.variant ?? "default"} size={c.size ?? "default"} disabled={disabled} invalid={invalid}>{(c.text : String)}</Button>;
			case "badge": <Badge variant={c.variant ?? "default"}>{(c.text : String)}</Badge>;
			case "input": <Input value={new Signal((c.text : String) ?? "")} placeholder={c.placeholder} disabled={disabled} invalid={invalid}/>;
			case "checkbox": <Checkbox checked={new Signal(c.checked == true)} disabled={disabled} invalid={invalid}/>;
			case "switch": <Switch on={new Signal(c.checked == true)} size={c.size ?? "default"} disabled={disabled}/>;
			case "label": <Label>{(c.text : String)}</Label>;
			case "card":
				<Card>
					<CardHeader>
						<CardTitle>{(c.title : String)}</CardTitle>
						<CardDescription>{(c.description : String)}</CardDescription>
						<CardAction><Button variant="link">{(c.action : String)}</Button></CardAction>
					</CardHeader>
					<CardContent>{(c.text : String)}</CardContent>
					<CardFooter><Button>{(c.footer : String)}</Button></CardFooter>
				</Card>;
			case other: throw 'FidelityTest: no widget for $other';
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
		var failed = 0;
		for (c in cases) {
			var w:Int = c.w, h:Int = c.h;
			var ui = new Ui(new DrawText(), W, H);
			ui.theme = Shadcn.sheet;
			ui.dark = c.dark == true;
			var frame = new Node("frame");
			frame.slot = "body";
			frame.style.set({width: w, height: h, padding: 16, fontFamily: "Inter", direction: c.block ? Column : Row, alignItems: Start});
			ui.root.append(frame);
			Render.render(widget(c), frame);
			ui.update();
			var states:Array<String> = c.states ?? [];
			var target = find(ui.root, c.component);
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
			var ok = mean < MEAN && far <= MAX_FAR * w * h;
			if (!ok) failed++;
			Sys.println('FidelityTest: ${c.name} ${ok ? "ok" : "FAILED"} (mean ${Math.round(mean * 100) / 100}, $far pixels off by more than $FAR)');
		}
		device.dispose();
		Sys.println('FidelityTest: ${cases.length} cases' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}
}
