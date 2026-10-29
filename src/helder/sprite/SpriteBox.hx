package helder.sprite;

import helder.gfx.Color;
import helder.gfx.Device;
import helder.gfx.Encoder;
import helder.gfx.Texture;

// A box in ui's layout drawing sprites: each frame it is painted, onDraw
// fills its SpriteBatch (begun at the box's size in ui's units, y down),
// and the batch is drawn into a texture of the box's size in pixels, before
// ui's pass (as a <Scene>'s box: helder.ui.draw.Renderer.beforePass), over
// a clear of background; ui then draws that texture as the box's content,
// under its children. Drawn again each frame while animate is set, else
// when asked (redraw). onReady is called once with the batch, before the
// first onDraw: where a program adds its textures.
class SpriteBox extends helder.ui.Node {
	public var animate = false;
	public var background = new Color(0, 0, 0, 0);
	public var onReady:Null<SpriteBatch->Void>;
	public var onDraw:Null<(batch:SpriteBatch, width:Float, height:Float) -> Void>;
	public var batch(default, null):Null<SpriteBatch>;

	var device:Null<Device>;
	var color:Null<Texture>;
	final retired:Array<Texture> = [];
	final retiredAt:Array<Int> = [];
	var records = 0;
	var tw = 0;
	var th = 0;
	var queued = -1;
	var units = 1.0;
	final id = -(++ids) - 1000000;

	static var ids = 0;

	public function new() {
		super("sprites");
	}

	// asks for a frame (a change outside animate)
	public function redraw()
		if (ui != null) ui.requestFrame();

	override public function hasContent():Bool
		return true;

	override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		var r = Std.downcast(canvas, helder.ui.draw.Renderer);
		if (r == null) return;
		if (animate && ui != null) ui.requestFrame();
		var pw = Std.int(Math.max(1, Math.round(width * r.scale))), ph = Std.int(Math.max(1, Math.round(height * r.scale)));
		if (batch == null) {
			device = r.device;
			batch = new SpriteBatch(r.device, RGBA8);
			if (onReady != null) onReady(batch);
		}
		if (pw != tw || ph != th) {
			if (color != null) {
				retired.push(color);
				retiredAt.push(records);
			}
			color = device.createTexture({width: pw, height: ph, renderTarget: true});
			tw = pw;
			th = ph;
		}
		while (retired.length > 0 && records >= retiredAt[0] + 2) {
			device.destroyTexture(retired.shift());
			retiredAt.shift();
		}
		batch.begin(width, height);
		if (onDraw != null) onDraw(batch, width, height);
		if (queued != r.frames) {
			queued = r.frames;
			r.beforePass(record);
		}
		r.gpuTexture(color, id, x, y, width, height);
	}

	function record(enc:Encoder) {
		records++;
		var c = color, b = batch;
		if (c == null || b == null) return;
		enc.beginPass({colors: [{load: Clear, clear: background, texture: c}]});
		b.flush(enc);
		enc.endPass();
	}

	public function dispose() {
		if (device != null) {
			if (color != null) device.destroyTexture(color);
			for (t in retired)
				device.destroyTexture(t);
			retired.resize(0);
			retiredAt.resize(0);
			if (batch != null) batch.dispose();
		}
		color = null;
		batch = null;
	}
}
