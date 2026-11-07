package helder.pack.android;

import helder.pack.android.Dex;

// The Java an app needs for views and listeners (classes.dex, written by
// Dex; the APK gets it when the program uses helder.os.android.Glue, and
// org.hxmc.Activity as its activity when it shows Android's views as its
// content: a class marked @:helder.android.views; Classes, a macro, tells
// helder.cli.Android):
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
// - org.hxmc.AccessProvider and org.hxmc.AccessDelegate: an
//   AccessibilityNodeProvider and a View.AccessibilityDelegate whose
//   methods are natives (helder.ui.draw.AndroidAccess registers them): a
//   drawn window's accessibility tree as the content view's virtual views.
// - org.hxmc.WebClient(int id), org.hxmc.WebChrome(int id): a
//   WebViewClient and a WebChromeClient whose callbacks call their static
//   native event(id, kind, object, a, b) as Glue's do (the program registers
//   it with Glue's handler: helder.os.android.Glue.adopt): WEB_STARTED,
//   WEB_FINISHED (the URL), WEB_ERROR (the WebResourceError; its code, 1 for
//   the main frame), WEB_NAVIGATED (doUpdateVisitedHistory: the URL),
//   WEB_OVERRIDE (shouldOverrideUrlLoading: the WebResourceRequest; kept
//   when non-zero), WEB_PROGRESS (the progress), WEB_TITLE (the title),
//   WEB_CONSOLE (the ConsoleMessage; handled), WEB_GONE (onRenderProcessGone:
//   handled); and shouldInterceptRequest,
//   on the WebView's own thread, calling the static native intercept(id,
//   request) for its WebResourceResponse (null: the network's).
// - org.hxmc.WebBridge(int id): the object a page reaches as a JavaScript
//   interface, its post(String) @JavascriptInterface calling the static
//   native post(id, message), on the WebView's JavaBridge thread
//   (helder.ui.platform.AndroidWebView).
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
	public static inline var WEB_STARTED = 10;
	public static inline var WEB_FINISHED = 11;
	public static inline var WEB_ERROR = 12;
	public static inline var WEB_NAVIGATED = 13;
	public static inline var WEB_OVERRIDE = 14;
	public static inline var WEB_PROGRESS = 15;
	public static inline var WEB_TITLE = 16;
	public static inline var WEB_CONSOLE = 17;
	public static inline var WEB_GONE = 18;

	static inline var GLUE = "Lorg/hxmc/Glue;";
	static inline var OBJECT = "Ljava/lang/Object;";
	static inline var VIEW = "Landroid/view/View;";
	static inline var HOLDER = "Landroid/view/SurfaceHolder;";

	public static function dex():haxe.io.Bytes
		return Dex.write([activity(), glue(), accessProvider(), accessDelegate(), webClient(), webChrome(), webBridge()]);

	static inline var NODE_INFO = "Landroid/view/accessibility/AccessibilityNodeInfo;";
	static inline var NODE_PROVIDER = "Landroid/view/accessibility/AccessibilityNodeProvider;";

	// a constructor calling its superclass's, of no arguments
	static function constructor(base:String):DexMethod
		return {
			name: "<init>",
			ret: "V",
			params: [],
			access: Dex.PUBLIC | Dex.CONSTRUCTOR,
			code: {registers: 1, ins: 1, outs: 1, insns: r -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", []), [0]).concat([RETURN_VOID])}
		};

	// org.hxmc.AccessProvider: an AccessibilityNodeProvider whose methods are
	// natives (helder.ui.draw.AndroidAccess's): a drawn window's nodes as
	// virtual views
	static function accessProvider():DexClass
		return {
			name: "Lorg/hxmc/AccessProvider;",
			access: Dex.PUBLIC | Dex.FINAL,
			superName: NODE_PROVIDER,
			interfaces: [],
			fields: [],
			methods: [
				constructor(NODE_PROVIDER),
				{name: "createAccessibilityNodeInfo", ret: NODE_INFO, params: ["I"], access: Dex.PUBLIC | Dex.NATIVE},
				{name: "performAction", ret: "Z", params: ["I", "I", "Landroid/os/Bundle;"], access: Dex.PUBLIC | Dex.NATIVE},
				{name: "findFocus", ret: NODE_INFO, params: ["I"], access: Dex.PUBLIC | Dex.NATIVE}
			]
		};

	// org.hxmc.AccessDelegate: a View.AccessibilityDelegate whose provider is a native's (the AccessProvider)
	static function accessDelegate():DexClass {
		var base = "Landroid/view/View$AccessibilityDelegate;";
		return {
			name: "Lorg/hxmc/AccessDelegate;",
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: [],
			fields: [],
			methods: [
				constructor(base),
				{name: "getAccessibilityNodeProvider", ret: NODE_PROVIDER, params: [VIEW], access: Dex.PUBLIC | Dex.NATIVE}
			]
		};
	}

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
	static inline var INVOKE_INTERFACE = 0x72;
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
	static function forward(name:String, params:Array<String>, kind:Int, a:Int, b:Int, ?ret:String, ?prepare:Refs->Array<Int>, ?cls:String, obj = 5):DexMethod {
		ret = ret ?? "V";
		cls = cls ?? GLUE;
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
					var c = [op(0, 4, 0x52), r.field(cls, "id", "I"), (1 << 8) | 0x13, kind, const4(2, 0), const4(3, 0)]; // iget v0, p0, id; const/16 v1, kind
					if (prepare != null) c = c.concat(prepare(r));
					c = c.concat(invoke(INVOKE_STATIC, r.method(cls, "event", "I", ["I", "I", OBJECT, "I", "I"]), [0, 1, obj, a, b]));
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

	// a class of an id (its constructor's int) and a static native event, as Glue
	static function withId(name:String, base:String, methods:Array<DexMethod>, ?natives:Array<DexMethod>):DexClass
		return {
			name: name,
			access: Dex.PUBLIC | Dex.FINAL,
			superName: base,
			interfaces: [],
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
						insns: r -> invoke(INVOKE_DIRECT, r.method(base, "<init>", "V", []), [0]).concat([op(1, 0, 0x59), r.field(name, "id", "I"), RETURN_VOID])
					}
				},
				{name: "event", ret: "I", params: ["I", "I", OBJECT, "I", "I"], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE}
			].concat(natives ?? []).concat(methods)
		};

	static inline var WEB_VIEW = "Landroid/webkit/WebView;";
	static inline var WEB_REQUEST = "Landroid/webkit/WebResourceRequest;";
	static inline var WEB_RESPONSE = "Landroid/webkit/WebResourceResponse;";
	static inline var STRING = "Ljava/lang/String;";

	// org.hxmc.WebClient: a WebViewClient (p_i is v(4 + i))
	static function webClient():DexClass {
		var cls = "Lorg/hxmc/WebClient;", error = "Landroid/webkit/WebResourceError;";
		return withId(cls, "Landroid/webkit/WebViewClient;", [
			{
				// (v0 the id, p0 v1, the view v2, the request v3: intercept(id, request)'s response)
				name: "shouldInterceptRequest",
				ret: WEB_RESPONSE,
				params: [WEB_VIEW, WEB_REQUEST],
				access: Dex.PUBLIC,
				code: {
					registers: 4,
					ins: 3,
					outs: 2,
					insns: r -> [op(0, 1, 0x52), r.field(cls, "id", "I")].concat(invoke(INVOKE_STATIC, r.method(cls, "intercept", WEB_RESPONSE, ["I", WEB_REQUEST]), [0, 3]))
						.concat([(0 << 8) | 0x0c, (0 << 8) | 0x11]) // move-result-object v0; return-object v0
				}
			},
			forward("onPageStarted", [WEB_VIEW, STRING, "Landroid/graphics/Bitmap;"], WEB_STARTED, 2, 3, null, null, cls, 6),
			forward("onPageFinished", [WEB_VIEW, STRING], WEB_FINISHED, 2, 3, null, null, cls, 6),
			forward("doUpdateVisitedHistory", [WEB_VIEW, STRING, "Z"], WEB_NAVIGATED, 2, 3, null, null, cls, 6),
			forward("shouldOverrideUrlLoading", [WEB_VIEW, WEB_REQUEST], WEB_OVERRIDE, 2, 3, "Z", null, cls, 6),
			// (v2: the error's code, v3: 1 for the main frame's request)
			forward("onRenderProcessGone", [WEB_VIEW, "Landroid/webkit/RenderProcessGoneDetail;"], WEB_GONE, 2, 3, "Z", null, cls, 6),
			forward("onReceivedError", [WEB_VIEW, WEB_REQUEST, error], WEB_ERROR, 2, 3, null,
				r -> invoke(INVOKE_INTERFACE, r.method(WEB_REQUEST, "isForMainFrame", "Z", []), [6]).concat([moveResult(3)])
					.concat(invoke(INVOKE_VIRTUAL, r.method(error, "getErrorCode", "I", []), [7])).concat([moveResult(2)]), cls, 7)
		], [{name: "intercept", ret: WEB_RESPONSE, params: ["I", WEB_REQUEST], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE}]);
	}

	// org.hxmc.WebChrome: a WebChromeClient
	static function webChrome():DexClass {
		var cls = "Lorg/hxmc/WebChrome;";
		return withId(cls, "Landroid/webkit/WebChromeClient;", [
			forward("onProgressChanged", [WEB_VIEW, "I"], WEB_PROGRESS, 6, 3, null, null, cls, 5),
			forward("onReceivedTitle", [WEB_VIEW, STRING], WEB_TITLE, 2, 3, null, null, cls, 6),
			forward("onConsoleMessage", ["Landroid/webkit/ConsoleMessage;"], WEB_CONSOLE, 2, 3, "Z", null, cls, 5)
		]);
	}

	// org.hxmc.WebBridge: post(String) for the page, its native on the bridge's thread
	static function webBridge():DexClass {
		var cls = "Lorg/hxmc/WebBridge;";
		var c = withId(cls, OBJECT, [
			{
				name: "post",
				ret: "V",
				params: [STRING],
				access: Dex.PUBLIC,
				annotations: ["Landroid/webkit/JavascriptInterface;"],
				code: {
					registers: 3,
					ins: 2,
					outs: 2,
					insns: r -> [op(0, 1, 0x52), r.field(cls, "id", "I")].concat(invoke(INVOKE_STATIC, r.method(cls, "message", "V", ["I", STRING]), [0, 2]))
						.concat([RETURN_VOID])
				}
			}
		], [{name: "message", ret: "V", params: ["I", STRING], access: Dex.PUBLIC | Dex.STATIC | Dex.NATIVE}]);
		return c;
	}

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
