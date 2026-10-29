package helder.ui.native;

import helder.ui.*;

// A platform control in the node tree: laid out by helder.ui's flexbox at
// the size the platform measures (its natural size, or the height for a
// given width), placed absolutely by its NativeHost, which keeps the native
// widget's properties in step with these. The platform's events come back
// through the callbacks.
class Control extends Node {
	public final kind:ControlKind;
	// a button's or checkbox's label, a field's text
	public var text(default, set):String = "";
	public var placeholder(default, set):String = "";
	public var checked(default, set):Bool = false;
	// a slider's or progress bar's value, in min...max (a progress bar: 0...1)
	public var value(default, set):Float = 0;
	public var min(default, set):Float = 0;
	public var max(default, set):Float = 1;
	public var step(default, set):Float = 0;
	public var enabled(default, set):Bool = true;

	public var onPress:Null<Void->Void>;
	public var onText:Null<String->Void>;
	public var onToggle:Null<Bool->Void>;
	public var onValue:Null<Float->Void>;
	public var onSubmit:Null<String->Void>;

	// the native widget's handle in its backend (0: none yet)
	public var handle(default, null) = 0;
	// the properties changed since the host last gave them to the widget
	@:allow(helder.ui.native) var stale = true;

	public function new(kind:ControlKind, ?tag:String) {
		super(tag == null ? "control" : tag);
		this.kind = kind;
		focusable = kind != Label && kind != Progress;
	}

	function changed(layout:Bool) {
		stale = true;
		if (layout) markDirty() else if (ui != null) ui.requestFrame();
	}

	function set_text(v:String):String {
		if (v == null) v = "";
		if (v != text) {
			text = v;
			changed(kind == Button || kind == CheckBox || kind == Label);
		}
		return v;
	}

	function set_placeholder(v:String):String {
		if (v != placeholder) {
			placeholder = v;
			changed(false);
		}
		return v;
	}

	function set_checked(v:Bool):Bool {
		if (v != checked) {
			checked = v;
			changed(false);
		}
		return v;
	}

	function set_value(v:Float):Float {
		if (v != value) {
			value = v;
			changed(false);
		}
		return v;
	}

	function set_min(v:Float):Float {
		if (v != min) {
			min = v;
			changed(false);
		}
		return v;
	}

	function set_max(v:Float):Float {
		if (v != max) {
			max = v;
			changed(false);
		}
		return v;
	}

	function set_step(v:Float):Float {
		if (v != step) {
			step = v;
			changed(false);
		}
		return v;
	}

	function set_enabled(v:Bool):Bool {
		if (v != enabled) {
			enabled = v;
			changed(false);
		}
		return v;
	}

	@:allow(helder.ui.native) function setHandle(h:Int)
		handle = h;

	// the platform's events: the property set (the widget has it already), then the callback (an event: the graph's writes land at its end)
	@:allow(helder.ui.native) function platformClick() {
		if (onPress != null) onPress();
		helder.view.graph.Graph.flush();
	}

	@:allow(helder.ui.native) function platformText(t:String) {
		@:bypassAccessor text = t;
		if (onText != null) onText(t);
		helder.view.graph.Graph.flush();
	}

	@:allow(helder.ui.native) function platformSubmit() {
		if (onSubmit != null) onSubmit(text);
		helder.view.graph.Graph.flush();
	}

	@:allow(helder.ui.native) function platformChecked(b:Bool) {
		@:bypassAccessor checked = b;
		if (onToggle != null) onToggle(b);
		helder.view.graph.Graph.flush();
	}

	@:allow(helder.ui.native) function platformValue(v:Float) {
		@:bypassAccessor value = v;
		if (onValue != null) onValue(v);
		helder.view.graph.Graph.flush();
	}

	override public function hasContent():Bool
		return true;

	// the platform's size for it (a host's backend; outside one, a guess from the text)
	override public function measureContent(engine:TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float, availHeight:Float):Size {
		var host = NativeHost.hostFor(ui);
		var s = if (host != null) {
			host.ensure(this);
			host.backend.measure(this, Math.isNaN(knownWidth) ? availWidth : knownWidth);
		} else new Size(text.length * 8 + 16, 24);
		return new Size(Math.isNaN(knownWidth) ? s.width : knownWidth, Math.isNaN(knownHeight) ? s.height : knownHeight);
	}

	override public function minContentWidth(engine:TextEngine):Float
		return kind == TextField || kind == Slider || kind == Progress ? 1 : measureContent(engine, Math.NaN, Math.NaN, Math.NaN, Math.NaN).width;

	// (the platform draws it)
	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {}
}
