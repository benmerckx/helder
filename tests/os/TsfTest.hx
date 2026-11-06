import helder.os.*;
import helder.os.win32.Com;
import helder.os.win32.Tsf;
import helder.os.win32.Tsf.IUnknownQi;
import helder.os.win32.User32;
import hxmc.unsafe.*;

// Windows' Text Services Framework for drawn text fields (helder.os.win32.Tsf;
// the window lane, on Windows and under Wine): the test is the input method
// (a TIP), the window's text store its document. Through msctf itself: the
// thread manager activated, the context pushed and the store's sink advised,
// an edit session (ITfContext.RequestEditSession) whose
// ITfInsertAtSelection.InsertTextAtSelection is told as TextInput; then a
// composition: TSF's own (ITfContextComposition.StartComposition: a range
// made a composition, its text TextEditing, EndComposition its commit) where
// msctf has it (not Wine's: its StartComposition is a stub, said so), and
// the store's ITfContextOwnerCompositionSink driven as TSF drives it with a
// composition view made here (its range's extent the test's) on every
// system: its text as TextEditing, changed by SetText, ended: TextEditing
// of nothing, then the commit as TextInput; the store's GetText, GetTextExt
// (the caret's rectangle on the screen: the candidates' place), a text
// changed outside the composition (TextReplace), the program's own change
// of the field told to TSF. With HELDER_NO_TSF=1: no store, IMM32's windows.
//   TsfTest
class TsfTest {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('TsfTest: ${ok ? "ok" : "FAIL"}: $what${detail == "" ? "" : " (" + detail + ")"}');
		if (!ok) failed++;
	}

	static final events:Array<String> = [];

	static function main() {
		var window = new Window("TsfTest", 240, 120);
		var frames = 0;
		App.run(() -> {
			frames++;
			if (frames == 3) {
				run(window);
				App.quit();
			}
			App.wait(0.02);
		}, e -> switch e.kind {
			case TextInput:
				events.push("input:" + e.text);
			case TextEditing:
				events.push("editing:" + e.text + "@" + e.x);
			case TextReplace:
				events.push('replace:${e.x}-${e.y}:${e.text}');
			case Close:
				window.close();
			case _:
		});
		Sys.println('TsfTest: ' + (failed == 0 ? "ok" : '$failed FAILED'));
		Sys.exit(failed > 0 ? 1 : 0);
	}

	static function took():String {
		var s = events.join(" | ");
		events.resize(0);
		return s;
	}

	static function wine():Bool
		return Arena.scopedValue(a -> !Ntdll.GetProcAddress(Ntdll.GetModuleHandleW(a.wstring("ntdll.dll")), a.cstring("wine_get_version")).isNull());

	static function run(window:Window) {
		var noTsf = Sys.getEnv("HELDER_NO_TSF") != null && Sys.getEnv("HELDER_NO_TSF") != "";
		var underWine = wine();
		Sys.println('TsfTest: ${underWine ? "under Wine" : "Windows"}${noTsf ? ", HELDER_NO_TSF" : ""}');
		window.startTextInput(10, 20, 1, 16);
		window.textContext("hello", 5, 5);
		var native = @:privateAccess window.native;
		var tsf:Null<Tsf> = cast @:privateAccess (cast native : helder.os.win32.Win32Window).tsf;
		if (noTsf) {
			check("HELDER_NO_TSF: no text store (IMM32's windows)", tsf == null && !Tsf.available());
			window.stopTextInput();
			return;
		}
		check("TSF: the thread manager activated", Tsf.available());
		check("TSF: the window's text store, its context pushed", tsf != null && !tsf.context.isNull());
		if (tsf == null || tsf.context.isNull()) return;
		check("TSF: the store's sink advised by msctf", tsf.advised());
		var ctx = tsf.context, client = @:privateAccess Tsf.clientId;

		// an input method's insertion through msctf
		session(ctx, client, ec -> {
			var ins = qi(ctx, IID_INSERT);
			if (ins.isNull()) return;
			Arena.scoped(a -> {
				var r:Ptr<Ptr> = a.alloc(8);
				r.value = Ptr.nil();
				ITfInsertAtSelection.InsertTextAtSelection(ins, ec, 0, a.wstring(" world"), 6, r);
				Com.release(r.value);
			});
			Com.release(ins);
		});
		var t = took();
		check("ITfInsertAtSelection: TextInput", t == "input: world", t);
		window.textContext("hello world", 11, 11);

		// TSF's own composition (msctf's StartComposition, a composition sink of the test's)
		var own = -1, hasComposition = !qiRelease(ctx, IID_CONTEXT_COMPOSITION);
		if (hasComposition) session(ctx, client, ec -> {
			var ins = qi(ctx, IID_INSERT), comp = qi(ctx, IID_CONTEXT_COMPOSITION);
			Arena.scoped(a -> {
				var r:Ptr<Ptr> = a.alloc(8), c:Ptr<Ptr> = a.alloc(8);
				r.value = c.value = Ptr.nil();
				// (TF_IAS_NO_DEFAULT_COMPOSITION: the composition StartComposition's alone)
				ITfInsertAtSelection.InsertTextAtSelection(ins, ec, 0x80000000, a.wstring("あ"), 1, r);
				if (!r.value.isNull()) {
					own = ITfContextComposition.StartComposition(comp, ec, r.value, CompositionSink.make(), c);
					if (own >= 0) composition = c.value;
					Com.release(r.value);
				}
			});
			Com.release(ins);
			Com.release(comp);
		});
		t = took();
		if (underWine && (!hasComposition || own == 0x80004001))
			Sys.println("TsfTest: Wine: no ITfContextComposition (or a stub StartComposition): TSF's own composition not checked here");
		else if (own < 0)
			// (Windows' msctf gave E_INVALIDARG on CI: a composition is a text service's, and the
			// test's edit sessions run under the program's own client id; the store's sink below is
			// driven as msctf drives it instead)
			Sys.println('TsfTest: StartComposition refused under the program\'s own client id (hr 0x${StringTools.hex(own)}): TSF\'s own composition not checked ($t)');
		else {
			check("ITfContextComposition.StartComposition: the composition as TextEditing", own >= 0 && t == "editing:あ@1", 'hr 0x${StringTools.hex(own)}: $t');
			if (own >= 0 && !composition.isNull()) {
				var c = composition;
				session(ctx, client, ec -> ITfComposition.EndComposition(c, ec));
				Com.release(composition);
				composition = Ptr.nil();
				t = took();
				check("ITfComposition.EndComposition: committed", t == "editing:@0 | input:あ", t);
			}
		}
		// (the document and the field back to "hello world", whatever stood)
		var stood = docText(tsf, ctx, client);
		window.textContext(stood, stood.length, stood.length);
		if (stood.length > 11) session(ctx, client, ec -> Arena.scoped(a -> {
			var ch:Ptr<Int32> = a.alloc(12);
			IStore.SetText(tsf.block, 0, 11, stood.length, a.wstring(""), 0, ch);
		}));
		took();
		// (SetText outside a composition)
		window.textContext("hello world!", 12, 12);
		session(ctx, client, ec -> Arena.scoped(a -> {
			var ch:Ptr<Int32> = a.alloc(12);
			IStore.SetText(tsf.block, 0, 11, 12, a.wstring(""), 0, ch);
		}));
		t = took();
		check("SetText outside a composition: TextReplace", t == "replace:11-12:", t);
		window.textContext("hello world", 11, 11);

		// the store's composition sink driven as TSF drives it, its view the test's
		var sink = qi(tsf.block, IID_OWNER_SINK);
		check("the store: ITfContextOwnerCompositionSink", !sink.isNull());
		if (sink.isNull()) return;
		var view = FakeView.make();
		session(ctx, client, ec -> {
			Arena.scoped(a -> {
				var ok:Ptr<Int32> = a.alloc(4);
				ok.value = 0;
				IOwnerSink.OnStartComposition(sink, view, ok);
				check("OnStartComposition: accepted", ok.value == 1);
			});
			var ins = qi(ctx, IID_INSERT);
			Arena.scoped(a -> {
				var r:Ptr<Ptr> = a.alloc(8);
				r.value = Ptr.nil();
				// (TF_IAS_NO_DEFAULT_COMPOSITION: in the test's composition, not one of msctf's)
				ITfInsertAtSelection.InsertTextAtSelection(ins, ec, 0x80000000, a.wstring("かな"), 2, r);
				Com.release(r.value);
			});
			Com.release(ins);
			FakeView.start = 11;
			FakeView.length = 2;
		});
		t = took();
		check("a composition: TextEditing, nothing typed", t == "editing:かな@2", t);
		session(ctx, client, ec -> Arena.scoped(a -> {
			var ch:Ptr<Int32> = a.alloc(12);
			IStore.SetText(tsf.block, 0, 11, 13, a.wstring("仮名"), 2, ch);
		}));
		t = took();
		check("the composition changed (SetText): TextEditing", t == "editing:仮名@2", t);
		// (the program's field unchanged meanwhile: told, kept)
		window.textContext("hello world", 11, 11);
		session(ctx, client, ec -> IOwnerSink.OnEndComposition(sink, view));
		t = took();
		check("OnEndComposition: its end, then the commit typed", t == "editing:@0 | input:仮名", t);
		window.textContext("hello world仮名", 13, 13);
		// the document as TSF reads it, the caret's rectangle on the screen
		var text = "", rect = [0, 0, 0, 0], hr = -1;
		session(ctx, client, ec -> Arena.scoped(a -> {
			var buf:Ptr<UInt16> = a.alloc(128), got:Ptr<Int32> = a.alloc(4), runs:Ptr<Int32> = a.alloc(8), nruns:Ptr<Int32> = a.alloc(4), next:Ptr<Int32> = a.alloc(4);
			if (IStore.GetText(tsf.block, 0, -1, buf, 64, got, runs, 1, nruns, next) >= 0) {
				var b = new StringBuf();
				for (i in 0...got.value)
					b.addChar(buf[i]);
				text = b.toString();
			}
			var rc:Ptr<Int32> = a.alloc(16), clipped:Ptr<Int32> = a.alloc(4);
			hr = IStore.GetTextExt(tsf.block, 1, 11, 13, rc, clipped);
			rect = [rc[0], rc[1], rc[2], rc[3]];
		}));
		check("GetText: the document", text == "hello world仮名", text);
		var o = Arena.scopedValue(a -> {
			var p = a.make(POINT);
			User32.ClientToScreen(window.surface.handle, p);
			[p.value.x, p.value.y];
		});
		check("GetTextExt: the caret's rectangle on the screen", hr >= 0 && rect.join(",") == [o[0] + 10, o[1] + 20, o[0] + 11, o[1] + 36].join(","), 'hr 0x${StringTools.hex(hr)}: ${rect.join(",")}');
		// (outside a lock: TS_E_NOLOCK)
		Arena.scoped(a -> {
			var got:Ptr<Int32> = a.alloc(4);
			check("GetSelection without a lock: TS_E_NOLOCK", IStore.GetSelection(tsf.block, 0, 1, a.alloc(16), got) == 0x80040201);
		});
		// the program's own change, then the input method's selection read under a lock
		window.textContext("hello", 2, 4);
		var sel = [0, 0];
		session(ctx, client, ec -> Arena.scoped(a -> {
			var s:Ptr<Int32> = a.alloc(16), got:Ptr<Int32> = a.alloc(4);
			IStore.GetSelection(tsf.block, -1, 1, s, got);
			sel = [s[0], s[1]];
		}));
		check("the program's text and selection: the document's", sel.join(",") == "2,4", sel.join(","));
		Com.release(sink);
		window.stopTextInput();
		check("stopTextInput: no events", took() == "");
	}

	static var composition = Ptr.nil();

	// the store's document, read under a lock
	static function docText(tsf:Tsf, ctx:Ptr, client:Int):String {
		var text = "";
		session(ctx, client, ec -> Arena.scoped(a -> {
			var buf:Ptr<UInt16> = a.alloc(256), got:Ptr<Int32> = a.alloc(4), runs:Ptr<Int32> = a.alloc(8), nruns:Ptr<Int32> = a.alloc(4), next:Ptr<Int32> = a.alloc(4);
			if (IStore.GetText(tsf.block, 0, -1, buf, 128, got, runs, 1, nruns, next) >= 0) {
				var b = new StringBuf();
				for (i in 0...got.value)
					b.addChar(buf[i]);
				text = b.toString();
			}
		}));
		return text;
	}

	// (true: it has none)
	static function qiRelease(o:Ptr, iid:Ptr):Bool {
		var p = qi(o, iid);
		Com.release(p);
		return p.isNull();
	}

	static function qi(o:Ptr, iid:Ptr):Ptr
		return Arena.scopedValue(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			p.value = Ptr.nil();
			IUnknownQi.QueryInterface(o, iid, p) >= 0 ? p.value : Ptr.nil();
		});

	// an edit session of the test's, read-write and synchronous (TF_ES_SYNC | TF_ES_READWRITE)
	static function session(ctx:Ptr, client:Int, body:Int->Void) {
		Session.body = body;
		var hr = Arena.scopedValue(a -> {
			var h:Ptr<Int32> = a.alloc(4);
			h.value = -1;
			var r = ITfContext.RequestEditSession(ctx, client, Session.make(), 7, h);
			r < 0 ? r : h.value;
		});
		if (hr < 0) check("RequestEditSession", false, '0x${StringTools.hex(hr)}');
		Session.body = null;
	}

	static final IID_INSERT = Com.guid(0x55CE16BA, 0x3014, 0x41C1, [0x9C, 0xEB, 0xFA, 0xDE, 0x14, 0x46, 0xAC, 0x6C]);
	static final IID_CONTEXT_COMPOSITION = Com.guid(0xD40C8AAE, 0xAC92, 0x4FC7, [0x9A, 0x11, 0x0E, 0xE0, 0xE2, 0x3A, 0xA3, 0x9B]);
	static final IID_OWNER_SINK = Com.guid(0x5F20AA40, 0xB57A, 0x4F34, [0x96, 0xAB, 0x35, 0x76, 0xF3, 0x77, 0xCC, 0x79]);
}

// an ITfEditSession: the test's body in DoEditSession
class Session {
	public static var body:Null<Int->Void> = null;
	static var object = Ptr.nil();

	public static function make():Ptr {
		if (object.isNull()) {
			var t:Ptr<Ptr> = LibC.malloc(32);
			t[0] = Callback.addr(qi);
			t[1] = Callback.addr(ref);
			t[2] = Callback.addr(ref);
			t[3] = Callback.addr(doEditSession);
			object = LibC.malloc(8);
			(object : Ptr<Ptr>).value = t;
		}
		return object;
	}

	@:hxmc.callback static function qi(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int {
		out.value = self;
		return 0;
	}

	@:hxmc.callback static function ref(self:Ptr):Int
		return 1;

	@:hxmc.callback static function doEditSession(self:Ptr, ec:Int):Int {
		if (body != null) body(ec);
		return 0;
	}
}

// an ITfCompositionSink (StartComposition's): OnCompositionTerminated
class CompositionSink {
	static var object = Ptr.nil();

	public static function make():Ptr {
		if (object.isNull()) {
			var t:Ptr<Ptr> = LibC.malloc(32);
			t[0] = Callback.addr(qi);
			t[1] = Callback.addr(ref);
			t[2] = Callback.addr(ref);
			t[3] = Callback.addr(terminated);
			object = LibC.malloc(8);
			(object : Ptr<Ptr>).value = t;
		}
		return object;
	}

	@:hxmc.callback static function qi(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int {
		out.value = self;
		return 0;
	}

	@:hxmc.callback static function ref(self:Ptr):Int
		return 1;

	@:hxmc.callback static function terminated(self:Ptr, ec:Int, comp:Ptr):Int
		return 0;
}

// an ITfCompositionView whose GetRange gives an ITfRangeACP of the test's extent
class FakeView {
	public static var start = 0;
	public static var length = 0;
	static var view = Ptr.nil();
	static var range = Ptr.nil();

	public static function make():Ptr {
		if (view.isNull()) {
			var v:Ptr<Ptr> = LibC.malloc(40);
			v[0] = Callback.addr(qi);
			v[1] = Callback.addr(ref);
			v[2] = Callback.addr(ref);
			v[3] = Callback.addr(stub);
			v[4] = Callback.addr(getRange);
			view = LibC.malloc(8);
			(view : Ptr<Ptr>).value = v;
			var r:Ptr<Ptr> = LibC.malloc(8 * 27);
			r[0] = Callback.addr(qi);
			r[1] = Callback.addr(ref);
			r[2] = Callback.addr(ref);
			for (i in 3...25)
				r[i] = Callback.addr(stub);
			r[25] = Callback.addr(getExtent);
			r[26] = Callback.addr(stub);
			range = LibC.malloc(8);
			(range : Ptr<Ptr>).value = r;
		}
		return view;
	}

	@:hxmc.callback static function qi(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int {
		out.value = self;
		return 0;
	}

	@:hxmc.callback static function ref(self:Ptr):Int
		return 1;

	@:hxmc.callback static function stub(self:Ptr):Int
		return 0x80004001;

	@:hxmc.callback static function getRange(self:Ptr, out:Ptr<Ptr>):Int {
		out.value = range;
		return 0;
	}

	@:hxmc.callback static function getExtent(self:Ptr, anchor:Ptr<Int32>, n:Ptr<Int32>):Int {
		anchor.value = start;
		n.value = length;
		return 0;
	}
}

@:build(helder.os.win32.Com.build())
class ITfContext {
	@:slot(3) static function RequestEditSession(self:Ptr, client:Int, session:Ptr, flags:Int, hr:Ptr<Int32>):Int;
}

@:build(helder.os.win32.Com.build())
class ITfInsertAtSelection {
	@:slot(3) static function InsertTextAtSelection(self:Ptr, ec:Int, flags:Int, text:Ptr, n:Int, range:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class ITfContextComposition {
	@:slot(3) static function StartComposition(self:Ptr, ec:Int, range:Ptr, sink:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
class ITfComposition {
	@:slot(6) static function EndComposition(self:Ptr, ec:Int):Int;
}

@:build(helder.os.win32.Com.build())
class IOwnerSink {
	@:slot(3) static function OnStartComposition(self:Ptr, view:Ptr, ok:Ptr<Int32>):Int;
	@:slot(5) static function OnEndComposition(self:Ptr, view:Ptr):Int;
}

// (the store's ITextStoreACP, called as TSF calls it)
@:build(helder.os.win32.Com.build())
class IStore {
	@:slot(8) static function GetSelection(self:Ptr, index:Int, count:Int, sel:Ptr, got:Ptr<Int32>):Int;
	@:slot(10) static function GetText(self:Ptr, start:Int, end:Int, plain:Ptr, want:Int, got:Ptr<Int32>, runs:Ptr, wantRuns:Int, gotRuns:Ptr<Int32>,
		next:Ptr<Int32>):Int;
	@:slot(11) static function SetText(self:Ptr, flags:Int, start:Int, end:Int, text:Ptr, n:Int, change:Ptr<Int32>):Int;
	@:slot(26) static function GetTextExt(self:Ptr, view:Int, start:Int, end:Int, rc:Ptr<Int32>, clipped:Ptr<Int32>):Int;
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32") extern class Ntdll {
	static function GetModuleHandleW(name:Ptr):Ptr;
	static function GetProcAddress(module:Ptr, name:Ptr):Ptr;
}
