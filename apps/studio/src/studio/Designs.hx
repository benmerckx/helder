package studio;

import helder.ui.*;
import helder.ui.view.Interpreter.Interpreted;
import studio.Project;

using StringTools;

// The design files' frames on the canvas (DESIGN.md): each interpreted in
// the studio's own process (helder.ui.view.Interpreter) from its file's
// text as the studio has it (Docs: an edit draws it again at once, nothing
// built or run), its nodes in the canvas' world beside the stories'
// images. A click in one selects its node directly, from the nodes' boxes
// and the offsets of their markup (no program to ask).
class Designs {
	final studio:Studio;
	// each file's last read: its text, its frames (null: it does not read, why)
	final read = new Map<String, {text:String, design:Null<DesignFile>, error:Null<String>}>();
	// each screen's frame as last drawn
	final drawn = new Map<String, Interpreted>();
	// (the images by path read: when, what)
	final images = new Map<String, {t:Float, image:Dynamic}>();
	var shown = false;
	// (the selection's node as last told: its box and colours)
	var followed = "";

	public function new(studio)
		this.studio = studio;

	// a design screen's content: its frame interpreted (it reads the file's
	// text: drawn again when it changes), or why it is not
	public function content(name:String):Any {
		studio.docs.version();
		studio.project.version();
		var info = studio.project.screen(name);
		if (info == null) return "no such frame";
		var r = file(info.file);
		var k = switch info.source {
			case Design(k): k;
			case _: -1;
		}
		if (r.design == null || k < 0 || k >= r.design.frames.length) {
			drawn.remove(info.name);
			return r.error ?? "no such frame";
		}
		var made = interpret(info.file, r.design.frames[k]);
		drawn.set(info.name, made);
		return made;
	}

	function interpret(file:String, fr:DesignFile.Frame):Interpreted
		return new Interpreted(fr.root, fr.base, src -> image(haxe.io.Path.normalize(haxe.io.Path.directory(file) + "/" + src)));

	// an image's size in points (its pixels; an SVG's viewBox)
	public function imageSize(path:String):{w:Float, h:Float} {
		var img:Dynamic = image(path);
		if (Std.isOfType(img, helder.ui.Svg)) {
			var s:helder.ui.Svg = img;
			return {w: s.width, h: s.height};
		}
		var i:helder.image.Image = img;
		return {w: i.width, h: i.height};
	}

	// an image by its path (a design's src="logo.png", from its file's
	// folder): read and decoded once (again when the file changes), an SVG
	// parsed; helder.image's, natively
	public function image(path:String):Dynamic {
		#if (hxmc.target == "wasm32-wasi")
		throw "an image by path: not in the browser yet";
		#else
		if (!sys.FileSystem.exists(path)) throw 'no such file';
		var t = sys.FileSystem.stat(path).mtime.getTime();
		var c = images.get(path);
		if (c != null && c.t == t) return c.image;
		var b = sys.io.File.getBytes(path);
		var img:Dynamic = path.toLowerCase().endsWith(".svg") ? helder.ui.Svg.parse(b.toString()) : helder.image.Image.decode(b);
		images.set(path, {t: t, image: img});
		return img;
		#end
	}

	// a design screen's frame mounted on its own, offscreen at its size (MCP's
	// run.tree and run.snap: whatever the canvas shows now); null: no such frame
	public function offscreen(name:String):Null<{ui:Ui, made:Interpreted, width:Int, height:Int}> {
		var info = studio.project.screen(name);
		var k = info == null ? -1 : switch info.source {
			case Design(k): k;
			case _: -1;
		}
		if (k < 0) return null;
		var r = file(info.file);
		if (r.design == null) throw '${info.file}: ${r.error}';
		var fr = r.design.frames[k];
		var ui = new Ui(Main.window == null ? new helder.story.StoryText() : Main.window.ui.text, fr.width, fr.height);
		var made = interpret(info.file, fr);
		helder.view.Render.render(made, ui.root);
		ui.update();
		return {ui: ui, made: made, width: fr.width, height: fr.height};
	}

	function file(path:String):{text:String, design:Null<DesignFile>, error:Null<String>} {
		var text = studio.docs.get(path).text;
		var r = read.get(path);
		if (r != null && r.text == text) return r;
		r = try {text: text, design: new DesignFile(text), error: null} catch (e:Dynamic) {text: text, design: null, error: Std.string(e)};
		read.set(path, r);
		return r;
	}

	// a design screen's frame drawn offscreen (scale: pixels a point), as
	// the store's screenshots are (its own device, headless): RGBA8 rows
	public function pixels(name:String, scale = 2.0):{pixels:haxe.io.Bytes, width:Int, height:Int} {
		#if (hxmc.target == "wasm32-wasi")
		throw "a design's frame as pixels: not in the browser yet";
		#else
		var o = offscreen(name);
		if (o == null) throw 'no design frame $name';
		var w = Math.round(o.width * scale), h = Math.round(o.height * scale);
		var device = helder.gfx.Device.create(helder.os.Surface.headless(w, h));
		try {
			o.ui.scale = scale;
			o.ui.update();
			var r = new helder.ui.draw.Renderer(device);
			r.scale = scale;
			var px = haxe.io.Bytes.alloc(w * h * 4);
			var enc = device.beginFrame();
			enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1)}]});
			r.begin(w, h);
			o.ui.paint(r);
			r.end(enc);
			enc.endPass();
			device.readPixels(px);
			device.endFrame();
			device.dispose();
			return {pixels: px, width: w, height: h};
		} catch (e:Dynamic) {
			device.dispose();
			throw e;
		}
		#end
	}

	#if (hxmc.target == "wasm32-wasi")
	// (in the browser: drawn by the studio's device into a render target, a
	// pass before its next frame, one snap at a time (one renderer's
	// buffers); the page reads it back, WebGPU's way: asynchronously)
	var snapper:Null<helder.ui.draw.Renderer> = null;
	var snapping = false;

	@:coroutine public function texture(name:String, scale = 2.0):{texture:helder.gfx.Texture, width:Int, height:Int} {
		var win = Main.window;
		if (win == null) throw "no window";
		while (snapping) helder.async.Async.delay(0.01);
		var o = offscreen(name);
		if (o == null) throw 'no design frame $name';
		var w = Math.round(o.width * scale), h = Math.round(o.height * scale);
		var device = win.device;
		var t = device.createTexture({width: w, height: h, renderTarget: true});
		var r = snapper ?? (snapper = new helder.ui.draw.Renderer(device, null, RGBA8));
		r.scale = scale;
		o.ui.scale = scale;
		o.ui.update();
		var drawn = false, late = false;
		snapping = true;
		win.renderer.nextPass(enc -> {
			if (late) return;
			enc.beginPass({colors: [{load: Clear, clear: new helder.gfx.Color(1, 1, 1), texture: t}]});
			r.begin(w, h);
			o.ui.paint(r);
			r.end(enc);
			enc.endPass();
			drawn = true;
		});
		win.ui.requestFrame();
		var t0 = haxe.Timer.stamp();
		while (!drawn && haxe.Timer.stamp() - t0 < 5) helder.async.Async.delay(0.01);
		snapping = false;
		if (drawn) return {texture: t, width: w, height: h};
		late = true;
		device.destroyTexture(t);
		throw '$name: not drawn (no frame in 5 s: the tab in the background?)';
	}
	#end

	// the node at (x, y) of a design screen (its points), the offset of its markup (null: none there)
	public function pick(name:String, x:Float, y:Float):Null<{node:Node, at:Int}> {
		var d = drawn.get(name);
		if (d == null || d.nodes.length == 0) return null;
		var root = d.nodes[0];
		return hit(d, root, root.absX + x, root.absY + y);
	}

	function hit(d:Interpreted, n:Node, x:Float, y:Float):Null<{node:Node, at:Int}> {
		if (x < n.absX || y < n.absY || x >= n.absX + n.width || y >= n.absY + n.height || n.style.display == None) return null;
		var i = n.children.length;
		while (--i >= 0) {
			var h = hit(d, n.children[i], x, y);
			if (h != null) return h;
		}
		var at = d.sources.get(n);
		return at == null ? null : {node: n, at: at};
	}

	// a node's box in its frame (its points)
	public function box(name:String, n:Node):{x:Float, y:Float, width:Float, height:Float} {
		var d = drawn.get(name);
		var root = d == null || d.nodes.length == 0 ? n : d.nodes[0];
		return {x: n.absX - root.absX, y: n.absY - root.absY, width: n.width, height: n.height};
	}

	// the node a frame drew for the markup at at (null: none now)
	public function nodeAt(name:String, at:Int):Null<Node> {
		var d = drawn.get(name);
		if (d == null) return null;
		for (n => a in d.sources)
			if (a == at) return n;
		return null;
	}

	// each frame the studio draws: the first time every frame is drawn told
	// (the open's measure), the selection's box followed (an edit drew its
	// frame again: the node there now)
	public function follow(since:Float) {
		var p = studio.project;
		if (p == null) return;
		var frames = Lambda.count(p.screens, s -> s.source.match(Design(_)));
		if (!shown && frames > 0 && Lambda.count(p.screens, s -> s.source.match(Design(_)) && drawn.exists(s.name)) == frames) {
			shown = true;
			var ms = Math.round((haxe.Timer.stamp() - since) * 1000);
			var errors = Lambda.fold([for (d in drawn) d.errors.length], (a, b) -> a + b, 0);
			Sys.println('studio: $frames design frame(s) drawn $ms ms after opening ${p.name}, nothing built' + (errors > 0 ? ', $errors marked' : ''));
			studio.log("designs-shown", {ms: ms, frames: frames, errors: errors});
		}
		var sel = studio.selection.peek();
		if (sel == null || !drawn.exists(sel.screen)) return;
		var n = nodeAt(sel.screen, sel.start);
		if (n == null) return;
		var b = box(sel.screen, n);
		var color = n.style.color == null ? null : "#" + StringTools.hex((n.style.color : Int), 8).toLowerCase();
		var background = "#" + StringTools.hex((n.style.background : Int), 8).toLowerCase();
		var key = '${sel.screen} ${sel.start} ${b.x} ${b.y} ${b.width} ${b.height} ${n.style.opacity} $color $background';
		if (key == followed) return;
		followed = key;
		var next:Studio.Selection = Reflect.copy(sel);
		next.x = b.x;
		next.y = b.y;
		next.width = b.width;
		next.height = b.height;
		next.opacity = n.style.opacity;
		studio.selection(next);
		studio.log("selection", {screen: next.screen, tag: n.tag, rect: [next.x, next.y, next.width, next.height], opacity: next.opacity,
			text: Std.isOfType(n, TextNode) ? (cast n : TextNode).text : null, color: color, background: background});
	}
}
