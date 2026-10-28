package helder.pack.android;

import helder.pack.android.Dex;

// The Java an app needs for views and listeners (classes.dex, written by
// Dex; the APK gets it when the program uses helder.os.android.Glue, and
// org.hxmc.Activity as its activity when it uses Android's views:
// helder.ui.native.NativeHost; Classes, a macro, tells helder.cli.Android):
//
// - org.hxmc.Activity, the APK's activity: NativeActivity (which loads the
//   program's library and runs it as without classes.dex), whose window
//   then draws views again: onCreate gives back the surface and the input
//   queue NativeActivity took (Window.takeSurface(null),
//   takeInputQueue(null): no ANativeWindow, the views get the input) and
//   the window's default pixel format.
// - org.hxmc.Glue(int id): one listener for every kind of widget, whose
//   methods call its static native event(id, kind, object, a, b), which
//   the program registers (RegisterNatives: helder.os.android.Glue); kinds
//   and arguments: CLICK (View.OnClickListener), TEXT
//   (TextWatcher.afterTextChanged: the Editable), CHECKED
//   (CompoundButton's: the state), PROGRESS (SeekBar's: the progress, from
//   the user), EDITOR (TextView.OnEditorActionListener: the action;
//   handled when event returns non-zero), LAYOUT
//   (View.OnLayoutChangeListener: the width and height), SURFACE_CREATED,
//   SURFACE_CHANGED (width, height), SURFACE_DESTROYED
//   (SurfaceHolder.Callback: the holder), KEY (View.OnKeyListener: the key
//   code and the action; handled when non-zero).
// The classes keep hxmc's names (org.hxmc.*), which helder.os.android
// looks up. Ported from hxmc (hxmc.android.Glue), MIT.
class Glue {
	public static inline var ACTIVITY = "org.hxmc.Activity";

	public static inline var CLICK = 0;
	public static inline var TEXT = 1;
	public static inline var CHECKED = 2;
	public static inline var PROGRESS = 3;
	public static inline var EDITOR = 4;
	public static inline var LAYOUT = 5;
	public static inline var SURFACE_CREATED = 6;
	public static inline var SURFACE_CHANGED = 7;
	public static inline var SURFACE_DESTROYED = 8;
	public static inline var KEY = 9;

	static inline var GLUE = "Lorg/hxmc/Glue;";
	static inline var OBJECT = "Ljava/lang/Object;";
	static inline var VIEW = "Landroid/view/View;";
	static inline var HOLDER = "Landroid/view/SurfaceHolder;";

	public static function dex():haxe.io.Bytes
		return Dex.write([activity(), glue()]);

	// ---- Dalvik instructions (16-bit units)

	static inline function op(a:Int, b:Int, op:Int):Int
		return (b << 12) | (a << 8) | op;

	// invoke-* {regs}, method (35c: up to five registers of 4 bits)
	static function invoke(opcode:Int, method:Int, regs:Array<Int>):Array<Int> {
		var r = regs.concat([0, 0, 0, 0, 0]);
		return [(regs.length << 12) | (r[4] << 8) | opcode, method, (r[3] << 12) | (r[2] << 8) | (r[1] << 4) | r[0]];
	}

	static inline var INVOKE_VIRTUAL = 0x6e;
	static inline var INVOKE_SUPER = 0x6f;
	static inline var INVOKE_DIRECT = 0x70;
	static inline var INVOKE_STATIC = 0x71;
	static inline var RETURN_VOID = 0x000e;

	// const/4 vA, #b (-8..7)
	static inline function const4(a:Int, b:Int):Int
		return op(a, b & 15, 0x12);

	static inline function moveResult(a:Int):Int
		return (a << 8) | 0x0a;

	// ---- the classes

	static function activity():DexClass {
		var cls = "Lorg/hxmc/Activity;", base = "Landroid/app/NativeActivity;", window = "Landroid/view/Window;";
		return {
			name: cls,
			access: Dex.PUBLIC,
			superName: base,
			interfaces: [],
			fields: [],
			methods: [
				{
					name: "<init>",
					ret: "V",
					params: [],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {registers: 1, ins: 1, outs: 1, insns: r -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", []), [0]).concat([RETURN_VOID])}
				},
				{
					// (v0 the window, v1 null and 0, v2 this, v3 the bundle)
					name: "onCreate",
					ret: "V",
					params: ["Landroid/os/Bundle;"],
					access: Dex.PROTECTED,
					code: {
						registers: 4,
						ins: 2,
						outs: 2,
						insns: r -> invoke(INVOKE_SUPER, r.method(base, "onCreate", "V", ["Landroid/os/Bundle;"]), [2, 3])
							.concat(invoke(INVOKE_VIRTUAL, r.method("Landroid/app/Activity;", "getWindow", window, []), [2]))
							.concat([(0 << 8) | 0x0c, const4(1, 0)]) // move-result-object v0
							.concat(invoke(INVOKE_VIRTUAL, r.method(window, "takeSurface", "V", ["Landroid/view/SurfaceHolder$Callback2;"]), [0, 1]))
							.concat(invoke(INVOKE_VIRTUAL, r.method(window, "takeInputQueue", "V", ["Landroid/view/InputQueue$Callback;"]), [0, 1]))
							.concat(invoke(INVOKE_VIRTUAL, r.method(window, "setFormat", "V", ["I"]), [0, 1]))
							.concat([RETURN_VOID])
					}
				}
			]
		};
	}

	// a listener method calling event(id, kind, p1, a, b): v0 the id, v1 the
	// kind, v2 and v3 for the arguments (0 unless `prepare` sets them), the
	// parameters after them (p0 this: v4); a boolean result is event's != 0
	static function forward(name:String, params:Array<String>, kind:Int, a:Int, b:Int, ?ret:String, ?prepare:Refs->Array<Int>):DexMethod {
		ret = ret ?? "V";
		var ins = 1 + params.length;
		return {
			name: name,
			ret: ret,
			params: params,
			access: Dex.PUBLIC,
			code: {
				registers: 4 + ins,
				ins: ins,
				outs: 5,
				insns: r -> {
					var c = [op(0, 4, 0x52), r.field(GLUE, "id", "I"), (1 << 8) | 0x13, kind, const4(2, 0), const4(3, 0)]; // iget v0, p0, id; const/16 v1, kind
					if (prepare != null) c = c.concat(prepare(r));
					c = c.concat(invoke(INVOKE_STATIC, r.method(GLUE, "event", "I", ["I", "I", OBJECT, "I", "I"]), [0, 1, 5, a, b]));
					c.concat(ret == "Z" ? [moveResult(0), const4(1, 0), 0x0038, 3, const4(1, 1), (1 << 8) | 0x0f] : [RETURN_VOID]); // if-eqz v0, +3; return v1
				}
			}
		};
	}

	static inline function nothing(name:String, params:Array<String>):DexMethod
		return {
			name: name,
			ret: "V",
			params: params,
			access: Dex.PUBLIC,
			code: {registers: 1 + params.length, ins: 1 + params.length, outs: 0, insns: r -> [RETURN_VOID]}
		};

	static function glue():DexClass {
		var cs = "Ljava/lang/CharSequence;", seekBar = "Landroid/widget/SeekBar;";
		// (p_i is v(4 + i))
		inline function p(i:Int)
			return 4 + i;
		return {
			name: GLUE,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: OBJECT,
			interfaces: [
				"Landroid/view/View$OnClickListener;", "Landroid/text/TextWatcher;", "Landroid/widget/CompoundButton$OnCheckedChangeListener;",
				"Landroid/widget/SeekBar$OnSeekBarChangeListener;", "Landroid/widget/TextView$OnEditorActionListener;", "Landroid/view/View$OnLayoutChangeListener;",
				"Landroid/view/SurfaceHolder$Callback;", "Landroid/view/View$OnKeyListener;"
			],
			fields: [{name: "id", type: "I", access: Dex.PRIVATE | Dex.FINAL}],
			methods: [
				{
					name: "<init>",
					ret: "V",
					params: ["I"],
					access: Dex.PUBLIC | Dex.CONSTRUCTOR,
					code: {
						registers: 2,
						ins: 2,
						outs: 1,
						insns: r -> invoke(INVOKE_DIRECT, r.method(OBJECT, "<init>", "V", []), [0]).concat([op(1, 0, 0x59), r.field(GLUE, "id", "I"), RETURN_VOID]) // iput v1, v0, id
					}
				},
				{name: "event", ret: "I", params: ["I", "I", OBJECT, "I", "I"], access: Dex.PRIVATE | Dex.STATIC | Dex.NATIVE},
				forward("onClick", [VIEW], CLICK, 2, 3),
				forward("afterTextChanged", ["Landroid/text/Editable;"], TEXT, 2, 3),
				nothing("beforeTextChanged", [cs, "I", "I", "I"]),
				nothing("onTextChanged", [cs, "I", "I", "I"]),
				forward("onCheckedChanged", ["Landroid/widget/CompoundButton;", "Z"], CHECKED, p(2), 3),
				forward("onProgressChanged", [seekBar, "I", "Z"], PROGRESS, p(2), p(3)),
				nothing("onStartTrackingTouch", [seekBar]),
				nothing("onStopTrackingTouch", [seekBar]),
				forward("onEditorAction", ["Landroid/widget/TextView;", "I", "Landroid/view/KeyEvent;"], EDITOR, p(2), 3, "Z"),
				// (sub-int v2, right, left; sub-int v3, bottom, top)
				forward("onLayoutChange", [VIEW, "I", "I", "I", "I", "I", "I", "I", "I"], LAYOUT, 2, 3, null,
					r -> [(2 << 8) | 0x91, (p(2) << 8) | p(4), (3 << 8) | 0x91, (p(3) << 8) | p(5)]),
				forward("surfaceCreated", [HOLDER], SURFACE_CREATED, 2, 3),
				forward("surfaceChanged", [HOLDER, "I", "I", "I"], SURFACE_CHANGED, p(3), p(4)),
				forward("surfaceDestroyed", [HOLDER], SURFACE_DESTROYED, 2, 3),
				// (v3: the event's getAction())
				forward("onKey", [VIEW, "I", "Landroid/view/KeyEvent;"], KEY, p(2), 3, "Z",
					r -> invoke(INVOKE_VIRTUAL, r.method("Landroid/view/KeyEvent;", "getAction", "I", []), [p(3)]).concat([moveResult(3)]))
			]
		};
	}
}
