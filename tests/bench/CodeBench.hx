import haxe.Timer;
import helder.ui.*;
import helder.ui.code.CodeEditor;
import helder.ui.draw.DrawText;

// helder.ui.code's own work a frame, without the GPU renderer: a
// CodeEditor on a file (10,000 lines in the code-bench lane) in a Ui of
// helder.text's engine, painted into a canvas that draws nothing, each
// frame timed and its GC bytes counted (GcStats): a keystroke (its key
// down, text and key up through the Ui, the edit, highlighting, the frame
// laid out and painted), Enter, a block comment opened (the rest of the
// view highlighted again), the wheel's first pass down (lines laid out
// the first time) and back up (the steady state), and a frame with
// nothing changed.
//   CodeBench <file.tsx>
class CodeBench {
	static var ui:Ui;
	static var editor:CodeEditor;
	static final canvas = new NullCanvas();

	static function main() {
		var path = Sys.args()[0];
		var text = sys.io.File.getContent(path);
		ui = new Ui(new DrawText(), 900, 640);
		var t0 = Timer.stamp();
		editor = new CodeEditor(text, path);
		ui.root.append(editor);
		ui.update();
		ui.paint(canvas);
		Sys.println('code-bench: opened ${editor.model.lineCount} lines and drew the first frame: ${ms(Timer.stamp() - t0)} ms');
		ui.setFocus(editor.view);
		editor.goToLine(5000);
		editor.model.moveLineEnd();
		frame();
		// (warm: a few of each)
		for (_ in 0...20)
			key("a".code, "a");
		run("keystroke (a character typed)", 300, () -> key("x".code, "x"));
		// (its parts: the Ui's key events, the edit alone, the frame after it)
		run("  the Ui's key down and up (no edit)", 300, () -> {
			ui.keyDown(Key.SHIFT, Key.MOD_SHIFT);
			ui.keyUp(Key.SHIFT, 0);
		});
		run("  the edit alone (CodeModel.type)", 300, () -> editor.model.type("y"));
		run("  the frame after an edit", 300, () -> {
			@:privateAccess editor.model.laid[editor.model.lineOf(editor.model.primary.head)] = null;
			@:privateAccess editor.model.tokStart[editor.model.lineOf(editor.model.primary.head)] = -1;
			@:privateAccess editor.model.dirtyFrom = editor.model.lineOf(editor.model.primary.head);
			frame();
		});
		run("keystroke (Enter: a line added)", 100, () -> key(Key.ENTER, null));
		run("keystroke (Backspace)", 100, () -> key(Key.BACKSPACE, null));
		editor.goToLine(4990);
		// (a template opened before a line's first character: the lines after
		// it read again to the next backquote, all of it: the worst case; then taken back)
		editor.goToLine(4991);
		editor.model.moveLineStart();
		Sys.println('code-bench: (the template opened before "' + editor.model.line(editor.model.lineOf(editor.model.primary.head)) + '")');
		run("keystroke (` opened: to the next ` again)", 60, () -> {
			key("`".code, "`");
			key(Key.BACKSPACE, null);
		}, 2);
		run("wheel, lines laid out the first time", 400, () -> {
			ui.wheel(400, 300, 0, 60);
			frame();
		});
		run("wheel back up (steady state)", 400, () -> {
			ui.wheel(400, 300, 0, -60);
			frame();
		});
		var dir = 1;
		run("  scrolled by 60 px without an event", 400, () -> {
			if (!editor.view.scrollTo(0, editor.view.scrollTop + 60 * dir)) dir = -dir;
			frame();
		});
		run("a frame with nothing changed", 200, () -> frame());
		Sys.println('code-bench: ${editor.model.length} characters, ${editor.model.lineCount} lines, scrolled to ${editor.view.scrollTop} px, ${[for (l in @:privateAccess editor.model.laid) if (l != null) l].length} lines laid out, the view ${editor.view.width}x${editor.view.height}');
	}

	static function frame() {
		Clock.tick(Clock.now + 1 / 60);
		ui.update();
		ui.paint(canvas);
	}

	// a key through the Ui as a window gives it (its text for a character), then a frame
	static function key(code:Int, text:Null<String>) {
		ui.keyDown(code, 0);
		if (text != null) ui.textInput(text);
		ui.keyUp(code, 0);
		frame();
	}

	static function run(name:String, n:Int, f:Void->Void, per = 1) {
		var times = [], bytes = [];
		var gc0 = GcStats.collections();
		for (_ in 0...n) {
			var b0 = GcStats.bytes(), t0 = Timer.stamp();
			f();
			times.push((Timer.stamp() - t0) * 1000 / per);
			bytes.push((GcStats.bytes() - b0) / per);
		}
		times.sort(Reflect.compare);
		bytes.sort(Reflect.compare);
		inline function at(a:Array<Float>, p:Float):Float
			return a[Std.int(Math.min(a.length - 1, Math.floor(p * (a.length - 1) + 0.5)))];
		Sys.println('code-bench: ${StringTools.rpad(name, " ", 42)} median ${round(at(times, 0.5))} ms, p95 ${round(at(times, 0.95))} ms, max ${round(times[times.length - 1])} ms; '
			+ '${Std.int(at(bytes, 0.5))} GC bytes a frame (max ${Std.int(bytes[bytes.length - 1])}), ${GcStats.collections() - gc0} GCs');
	}

	static inline function ms(s:Float):Float
		return round(s * 1000);

	static inline function round(x:Float):Float
		return Math.round(x * 1000) / 1000;
}

// (draws nothing: the editor's work alone)
class NullCanvas implements Canvas {
	public function new() {}

	public function translate(dx:Float, dy:Float) {}

	public function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners) {}

	public function popClip() {}

	public function pushOpacity(alpha:Float) {}

	public function popOpacity() {}

	public function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function popTransform() {}

	public function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges) {}

	public function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>) {}

	public function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float, ?corners:Corners) {}

	public function path(p:Path, fill:Null<Paint>, ?stroke:Stroke) {}

	public function image(img:helder.image.Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners) {}

	public function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>) {}

	public function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>) {}
}
