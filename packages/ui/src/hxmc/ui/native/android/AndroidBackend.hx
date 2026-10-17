package hxmc.ui.native.android;

import hxmc.os.android.Activity;
import hxmc.os.android.Glue;
import hxmc.os.android.Jni;
import hxmc.os.android.MainThread;
import hxmc.os.android.Native;
import hxmc.ui.*;
import hxmc.ui.native.*;
import hxmc.unsafe.*;

// NativeBackend on Android: android.widget's views through JNI
// (hxmc.os.android.Jni), in an AbsoluteLayout that is the activity's
// content view, each placed with its LayoutParams at the layout's position
// and size; Button, TextView (labels: their node's font, size and colour),
// EditText (one line), CheckBox, SeekBar, ProgressBar. Sizes are the
// layout's units, dp: pixels over the screen's density. Measured with the
// views' own onMeasure; text with a TextView kept for it. Accessibility
// is the views': TalkBack and the system's tools read them as they are.
// Views live on the main thread (MainThread), so everything here runs
// there: openWindow hands its work over; run (NativeHost.run) starts the
// host's steps on Choreographer's frames there, which go on while the UI
// asks for one, and waits on the program's thread until the window closes
// or the activity goes. Listeners (hxmc.os.android.Glue, classes.dex)
// bring the views' events back; what update sets itself is not reported.
class AndroidBackend implements NativeBackend implements NativeDriver {
	static var nextHandle = 1;

	final views = new Map<Int, Ptr>();
	final nodes = new Map<Int, Node>();
	final listeners = new Map<Int, Int>();
	// each view's LayoutParams as last set (x, y, width, height in pixels)
	final placed = new Map<Int, String>();
	var host:Null<NativeHost>;
	var root = Ptr.nil();
	var measurer = Ptr.nil();
	var measuredFont = "";
	final typefaces = new Map<String, Ptr>();
	var density = 1.0;
	// the content's size in pixels
	var width = 0;
	var height = 0;
	var open = false;
	var updating = false;

	public function new() {}

	public function openWindow(title:String, w:Int, h:Int, host:NativeHost) {
		this.host = host;
		MainThread.run(() -> {
			J.init();
			var act = Jni.activity;
			var metrics = Jni.obj(Jni.obj(act, J.getResources), J.getDisplayMetrics);
			density = JniEnv.GetFloatField(Jni.env, metrics, J.density);
			width = JniEnv.GetIntField(Jni.env, metrics, J.widthPixels);
			height = JniEnv.GetIntField(Jni.env, metrics, J.heightPixels);
			root = Jni.global(Jni.newObject(J.absoluteLayout, J.absoluteLayoutNew, act.toI64()));
			// (the system bars' insets as the root's padding)
			Jni.call(root, J.setFitsSystemWindows, 1);
			var l = Glue.listener((kind, o, a, b) -> {
				// (the content's size, inside the padding)
				var nw = a - Jni.int(root, J.getPaddingLeft) - Jni.int(root, J.getPaddingRight);
				var nh = b - Jni.int(root, J.getPaddingTop) - Jni.int(root, J.getPaddingBottom);
				if (nw != width || nh != height) {
					width = nw;
					height = nh;
					if (this.host != null) @:privateAccess this.host.windowResized();
				}
				0;
			});
			Jni.call(root, J.addOnLayoutChangeListener, l.obj.toI64());
			Jni.call(act, J.setContentView, root.toI64());
			var t = Jni.string(title);
			Jni.call(act, J.setTitle, t.toI64());
			measurer = Jni.global(Jni.newObject(J.textView, J.textViewNew, act.toI64()));
		});
		open = true;
	}

	// the host's steps on the main thread's frames, the program's thread
	// waiting until the window closes (or the activity is destroyed)
	public static function run(host:NativeHost) {
		start(host);
		while (!host.closed) {
			if (Activity.destroyed != 0) {
				@:privateAccess host.windowClosed();
				break;
			}
			MainThread.wait(-1);
		}
	}

	// the steps started, without waiting (tests drive the host with MainThread.run meanwhile)
	public static function start(host:NativeHost)
		MainThread.run(() -> {
			MainThread.onFrame = () -> {
				host.step();
				!host.closed && (host.ui.needsFrame || Clock.active);
			};
			MainThread.requestFrame();
		});

	public function closeWindow() {
		if (!open) return;
		open = false;
		Android.ANativeActivity_finish(Activity.activity);
		MainThread.onFrame = null;
		MainThread.wake();
	}

	public function windowWidth():Int
		return Math.round(width / density);

	public function windowHeight():Int
		return Math.round(height / density);

	public function create(n:Node):Int {
		var h = nextHandle++, act = Jni.activity.toI64();
		var v = if (Std.isOfType(n, Control)) {
			var c:Control = cast n;
			switch c.kind {
				case Button:
					var b = Jni.newObject(J.button, J.buttonNew, act);
					listen(h, b, J.setOnClickListener);
					b;
				case Label:
					Jni.newObject(J.textView, J.textViewNew, act);
				case TextField:
					var e = Jni.newObject(J.editText, J.editTextNew, act);
					Jni.call(e, J.setSingleLine, 1);
					Jni.call(e, J.setImeOptions, 6); // EditorInfo.IME_ACTION_DONE
					var id = listen(h, e, J.addTextChangedListener);
					Jni.call(e, J.setOnEditorActionListener, listenerObj(id));
					e;
				case CheckBox:
					var b = Jni.newObject(J.checkBox, J.checkBoxNew, act);
					listen(h, b, J.setOnCheckedChangeListener);
					b;
				case Slider:
					var s = Jni.newObject(J.seekBar, J.seekBarNew, act);
					Jni.call(s, J.setMax, TICKS);
					listen(h, s, J.setOnSeekBarChangeListener);
					s;
				case Progress:
					// (@android:attr/progressBarStyleHorizontal)
					var p = Jni.newObject(J.progressBar, J.progressBarNew, act, 0, 0x01010078);
					Jni.call(p, J.setIndeterminate, 0);
					Jni.call(p, J.setMax, TICKS);
					p;
			}
		} else Jni.newObject(J.textView, J.textViewNew, act);
		var g = Jni.global(v);
		Jni.deleteLocal(v);
		views.set(h, g);
		nodes.set(h, n);
		Jni.call(root, J.addView, g.toI64());
		return h;
	}

	static inline var TICKS = 1000;

	// the listener objects by Glue id (kept until their view goes)
	final listenerObjs = new Map<Int, Ptr>();

	inline function listenerObj(id:Int):Int64
		return listenerObjs.get(id).toI64();

	// a Glue listener for the view's events, set with setter
	function listen(h:Int, view:Ptr, setter:Ptr):Int {
		var l = Glue.listener((kind, o, a, b) -> event(h, kind, o, a));
		listeners.set(h, l.id);
		listenerObjs.set(l.id, Jni.global(l.obj));
		Jni.call(view, setter, l.obj.toI64());
		Jni.deleteLocal(l.obj);
		return l.id;
	}

	function event(h:Int, kind:Int, o:Ptr, a:Int):Int {
		var n = nodes.get(h);
		if (updating || n == null || !Std.isOfType(n, Control)) return 0;
		var c:Control = cast n;
		switch kind {
			case Glue.CLICK:
				c.platformClick();
			case Glue.TEXT:
				c.platformText(Jni.text(o));
			case Glue.CHECKED:
				c.platformChecked(a != 0);
			case Glue.PROGRESS:
				c.platformValue(valueOf(c, a));
			case Glue.EDITOR:
				c.platformSubmit();
			case _:
		}
		return 0;
	}

	// a slider's value at a position of the bar (on its step)
	static function valueOf(c:Control, ticks:Int):Float {
		var v = c.min + ticks / TICKS * (c.max - c.min);
		return c.step > 0 ? Math.min(c.max, c.min + Math.round((v - c.min) / c.step) * c.step) : v;
	}

	static function ticksOf(c:Control, v:Float):Int
		return c.max > c.min ? Math.round((v - c.min) / (c.max - c.min) * TICKS) : 0;

	function setText(v:Ptr, s:String) {
		var js = Jni.string(s);
		Jni.call(v, J.setText, js.toI64());
		Jni.deleteLocal(js);
	}

	public function update(h:Int, n:Node) {
		var v = views.get(h);
		if (v == null) return;
		updating = true;
		if (Std.isOfType(n, Control)) {
			var c:Control = cast n;
			switch c.kind {
				case Button | Label:
					setText(v, c.text);
				case TextField:
					if (Jni.text(Jni.obj(v, J.getText)) != c.text) setText(v, c.text);
					var hint = Jni.string(c.placeholder);
					Jni.call(v, J.setHint, hint.toI64());
					Jni.deleteLocal(hint);
				case CheckBox:
					setText(v, c.text);
					Jni.call(v, J.setChecked, Jni.z(c.checked));
				case Slider:
					Jni.call(v, J.setProgress, ticksOf(c, c.value));
				case Progress:
					Jni.call(v, J.setProgress, Math.round((c.value < 0 ? 0 : c.value > 1 ? 1 : c.value) * TICKS));
			}
			Jni.call(v, J.setEnabled, Jni.z(c.enabled));
		} else if (Std.isOfType(n, TextNode)) {
			var t:TextNode = cast n;
			setText(v, t.text);
			font(v, t.font());
			var col:Color = t.textColor();
			Jni.call(v, J.setTextColor, (col.a << 24) | (col.r << 16) | (col.g << 8) | col.b);
			var align = t.textAlign();
			// (Gravity: TOP 48, and LEFT 3, CENTER_HORIZONTAL 1, RIGHT 5)
			var gravity = 48 | (align == Center ? 1 : align == Right ? 5 : 3);
			Jni.call(v, J.setGravity, gravity);
		}
		updating = false;
	}

	// a TextView's font: its size in pixels, a typeface of the family at the weight
	function font(v:Ptr, f:Font) {
		Jni.call(v, J.setTextSize, 0, Jni.f(f.size * density)); // TypedValue.COMPLEX_UNIT_PX
		var key = f.family + "/" + f.weight + (f.italic ? "i" : "");
		var tf = typefaces.get(key);
		if (tf == null) {
			var fam = Jni.string(f.family);
			var base = Jni.staticObj(J.typeface, J.typefaceCreate, fam.toI64(), 0);
			tf = Jni.global(Jni.staticObj(J.typeface, J.typefaceWeight, base.toI64(), f.weight, Jni.z(f.italic)));
			typefaces.set(key, tf);
		}
		Jni.call(v, J.setTypeface, tf.toI64());
	}

	public function place(h:Int, x:Float, y:Float, w:Float, ht:Float) {
		var v = views.get(h);
		if (v == null) return;
		var px = Math.round(x * density), py = Math.round(y * density), pw = Math.round(Math.max(1, w) * density),
			ph = Math.round(Math.max(1, ht) * density);
		var key = px + "," + py + "," + pw + "," + ph;
		if (placed.get(h) == key) return;
		placed.set(h, key);
		var lp = Jni.newObject(J.layoutParams, J.layoutParamsNew, pw, ph, px, py);
		Jni.call(v, J.setLayoutParams, lp.toI64());
		Jni.deleteLocal(lp);
	}

	public function destroy(h:Int) {
		var v = views.get(h);
		if (v == null) return;
		Jni.call(root, J.removeView, v.toI64());
		Jni.deleteGlobal(v);
		views.remove(h);
		nodes.remove(h);
		placed.remove(h);
		var id = listeners.get(h);
		if (id != null) {
			Glue.release(id);
			Jni.deleteGlobal(listenerObjs.get(id));
			listenerObjs.remove(id);
			listeners.remove(h);
		}
	}

	// MeasureSpec: UNSPECIFIED 0, EXACTLY 1 << 30, AT_MOST 2 << 30
	function measured(v:Ptr, widthSpec:Int):Size {
		Jni.call(v, J.measure, widthSpec, 0);
		return new Size(Math.ceil(Jni.int(v, J.getMeasuredWidth) / density), Math.ceil(Jni.int(v, J.getMeasuredHeight) / density));
	}

	public function measure(c:Control, w:Float):Size {
		var v = views.get(c.handle);
		if (v == null) return new Size(0, 0);
		return measured(v, 0);
	}

	public function measureText(s:String, f:Font, maxWidth:Float):Size {
		var key = f.family + "/" + f.size + "/" + f.weight + (f.italic ? "i" : "");
		if (key != measuredFont) {
			font(measurer, f);
			measuredFont = key;
		}
		setText(measurer, s);
		return measured(measurer, Math.isNaN(maxWidth) ? 0 : (2 << 30) | Math.round(Math.max(1, maxWidth) * density));
	}

	public function pump(block:Bool):Bool {
		if (block && open && !MainThread.isMain()) MainThread.wait(-1);
		return open && Activity.destroyed == 0;
	}

	// --- NativeDriver (on the main thread): the views' own calls, their listeners following ---

	public function click(h:Int)
		Jni.bool(views.get(h), J.performClick);

	public function type(h:Int, s:String)
		setText(views.get(h), s);

	public function toggle(h:Int, on:Bool)
		Jni.call(views.get(h), J.setChecked, Jni.z(on));

	public function slide(h:Int, v:Float) {
		var c:Control = cast nodes.get(h);
		Jni.call(views.get(h), J.setProgress, ticksOf(c, v));
	}

	public function fieldText(h:Int):String
		return Jni.text(Jni.obj(views.get(h), J.getText));

	public function sliderValue(h:Int):Float
		return valueOf(cast nodes.get(h), Jni.int(views.get(h), J.getProgress));

	// where the view is in the content, as the layout's units
	public function allocation(h:Int):Array<Int> {
		var v = views.get(h);
		if (v == null) return [];
		var x = Jni.int(v, J.getLeft) - Jni.int(root, J.getPaddingLeft), y = Jni.int(v, J.getTop) - Jni.int(root, J.getPaddingTop);
		return [for (p in [x, y, Jni.int(v, J.getWidth), Jni.int(v, J.getHeight)]) Math.round(p / density)];
	}

	// (adb's screencap takes it)
	public function screenshot(path:String):Bool
		return false;

	// the view of a handle (a global reference)
	public function view(h:Int):Ptr
		return views.get(h);
}

// the classes and methods used, looked up once (on the main thread)
private class J {
	static var ready = false;
	public static var absoluteLayout:Ptr;
	public static var absoluteLayoutNew:Ptr;
	public static var layoutParams:Ptr;
	public static var layoutParamsNew:Ptr;
	public static var textView:Ptr;
	public static var button:Ptr;
	public static var editText:Ptr;
	public static var checkBox:Ptr;
	public static var seekBar:Ptr;
	public static var progressBar:Ptr;
	public static var typeface:Ptr;
	public static var textViewNew:Ptr;
	public static var buttonNew:Ptr;
	public static var editTextNew:Ptr;
	public static var checkBoxNew:Ptr;
	public static var seekBarNew:Ptr;
	public static var progressBarNew:Ptr;
	public static var getResources:Ptr;
	public static var getDisplayMetrics:Ptr;
	public static var density:Ptr;
	public static var widthPixels:Ptr;
	public static var heightPixels:Ptr;
	public static var setContentView:Ptr;
	public static var setTitle:Ptr;
	public static var addView:Ptr;
	public static var removeView:Ptr;
	public static var setLayoutParams:Ptr;
	public static var setFitsSystemWindows:Ptr;
	public static var addOnLayoutChangeListener:Ptr;
	public static var setOnClickListener:Ptr;
	public static var getPaddingLeft:Ptr;
	public static var getPaddingTop:Ptr;
	public static var getPaddingRight:Ptr;
	public static var getPaddingBottom:Ptr;
	public static var measure:Ptr;
	public static var getMeasuredWidth:Ptr;
	public static var getMeasuredHeight:Ptr;
	public static var setEnabled:Ptr;
	public static var performClick:Ptr;
	public static var getLeft:Ptr;
	public static var getTop:Ptr;
	public static var getWidth:Ptr;
	public static var getHeight:Ptr;
	public static var setText:Ptr;
	public static var getText:Ptr;
	public static var setHint:Ptr;
	public static var setTextSize:Ptr;
	public static var setTypeface:Ptr;
	public static var setTextColor:Ptr;
	public static var setGravity:Ptr;
	public static var setSingleLine:Ptr;
	public static var setImeOptions:Ptr;
	public static var addTextChangedListener:Ptr;
	public static var setOnEditorActionListener:Ptr;
	public static var setChecked:Ptr;
	public static var setOnCheckedChangeListener:Ptr;
	public static var setOnSeekBarChangeListener:Ptr;
	public static var setMax:Ptr;
	public static var setProgress:Ptr;
	public static var getProgress:Ptr;
	public static var setIndeterminate:Ptr;
	public static var typefaceCreate:Ptr;
	public static var typefaceWeight:Ptr;

	public static function init() {
		if (ready) return;
		ready = true;
		var m = Jni.method, cls = Jni.cls;
		var context = "(Landroid/content/Context;)V", cs = "(Ljava/lang/CharSequence;)V";
		var activity = cls("android.app.Activity"), view = cls("android.view.View"), group = cls("android.view.ViewGroup");
		absoluteLayout = cls("android.widget.AbsoluteLayout");
		absoluteLayoutNew = m(absoluteLayout, "<init>", context);
		layoutParams = cls("android.widget.AbsoluteLayout$LayoutParams");
		layoutParamsNew = m(layoutParams, "<init>", "(IIII)V");
		textView = cls("android.widget.TextView");
		button = cls("android.widget.Button");
		editText = cls("android.widget.EditText");
		checkBox = cls("android.widget.CheckBox");
		seekBar = cls("android.widget.SeekBar");
		progressBar = cls("android.widget.ProgressBar");
		typeface = cls("android.graphics.Typeface");
		textViewNew = m(textView, "<init>", context);
		buttonNew = m(button, "<init>", context);
		editTextNew = m(editText, "<init>", context);
		checkBoxNew = m(checkBox, "<init>", context);
		seekBarNew = m(seekBar, "<init>", context);
		progressBarNew = m(progressBar, "<init>", "(Landroid/content/Context;Landroid/util/AttributeSet;I)V");
		getResources = m(activity, "getResources", "()Landroid/content/res/Resources;");
		getDisplayMetrics = m(cls("android.content.res.Resources"), "getDisplayMetrics", "()Landroid/util/DisplayMetrics;");
		var metrics = cls("android.util.DisplayMetrics");
		density = Jni.field(metrics, "density", "F");
		widthPixels = Jni.field(metrics, "widthPixels", "I");
		heightPixels = Jni.field(metrics, "heightPixels", "I");
		setContentView = m(activity, "setContentView", "(Landroid/view/View;)V");
		setTitle = m(activity, "setTitle", cs);
		addView = m(group, "addView", "(Landroid/view/View;)V");
		removeView = m(group, "removeView", "(Landroid/view/View;)V");
		setLayoutParams = m(view, "setLayoutParams", "(Landroid/view/ViewGroup$LayoutParams;)V");
		setFitsSystemWindows = m(view, "setFitsSystemWindows", "(Z)V");
		addOnLayoutChangeListener = m(view, "addOnLayoutChangeListener", "(Landroid/view/View$OnLayoutChangeListener;)V");
		setOnClickListener = m(view, "setOnClickListener", "(Landroid/view/View$OnClickListener;)V");
		getPaddingLeft = m(view, "getPaddingLeft", "()I");
		getPaddingTop = m(view, "getPaddingTop", "()I");
		getPaddingRight = m(view, "getPaddingRight", "()I");
		getPaddingBottom = m(view, "getPaddingBottom", "()I");
		measure = m(view, "measure", "(II)V");
		getMeasuredWidth = m(view, "getMeasuredWidth", "()I");
		getMeasuredHeight = m(view, "getMeasuredHeight", "()I");
		setEnabled = m(view, "setEnabled", "(Z)V");
		performClick = m(view, "performClick", "()Z");
		getLeft = m(view, "getLeft", "()I");
		getTop = m(view, "getTop", "()I");
		getWidth = m(view, "getWidth", "()I");
		getHeight = m(view, "getHeight", "()I");
		setText = m(textView, "setText", cs);
		getText = m(textView, "getText", "()Ljava/lang/CharSequence;");
		setHint = m(textView, "setHint", cs);
		setTextSize = m(textView, "setTextSize", "(IF)V");
		setTypeface = m(textView, "setTypeface", "(Landroid/graphics/Typeface;)V");
		setTextColor = m(textView, "setTextColor", "(I)V");
		setGravity = m(textView, "setGravity", "(I)V");
		setSingleLine = m(textView, "setSingleLine", "(Z)V");
		setImeOptions = m(textView, "setImeOptions", "(I)V");
		addTextChangedListener = m(textView, "addTextChangedListener", "(Landroid/text/TextWatcher;)V");
		setOnEditorActionListener = m(textView, "setOnEditorActionListener", "(Landroid/widget/TextView$OnEditorActionListener;)V");
		var compound = cls("android.widget.CompoundButton");
		setChecked = m(compound, "setChecked", "(Z)V");
		setOnCheckedChangeListener = m(compound, "setOnCheckedChangeListener", "(Landroid/widget/CompoundButton$OnCheckedChangeListener;)V");
		setOnSeekBarChangeListener = m(seekBar, "setOnSeekBarChangeListener", "(Landroid/widget/SeekBar$OnSeekBarChangeListener;)V");
		setMax = m(progressBar, "setMax", "(I)V");
		setProgress = m(progressBar, "setProgress", "(I)V");
		getProgress = m(progressBar, "getProgress", "()I");
		setIndeterminate = m(progressBar, "setIndeterminate", "(Z)V");
		typefaceCreate = Jni.staticMethod(typeface, "create", "(Ljava/lang/String;I)Landroid/graphics/Typeface;");
		typefaceWeight = Jni.staticMethod(typeface, "create", "(Landroid/graphics/Typeface;IZ)Landroid/graphics/Typeface;");
	}
}
