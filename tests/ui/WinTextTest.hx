import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.widgets.EditableText;
import helder.os.win32.Com;
import helder.os.win32.Tsf;
import helder.os.win32.Tsf.IUnknownQi;
import helder.view.*;
import helder.view.graph.Graph.*;
import hxmc.unsafe.*;

// A drawn text field on Windows typed into through TSF (the window lane, on
// Windows and under Wine): the field focused, its text and caret the store's
// document (Window.textContext, from UiWindow's frames), an input method's
// insertion through msctf (ITfInsertAtSelection) typed into the field and
// its signal, a composition (the store's ITfContextOwnerCompositionSink, a
// view of the test's) shown in the field, not in its text, then committed.
//   WinTextTest
class WinTextTest implements Markup {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		Sys.println('WinTextTest: ${ok ? "ok" : "FAIL"}: $what' + (detail == null ? "" : " (" + detail + ")"));
		if (!ok) failed++;
	}

	static final IID_INSERT = Com.guid(0x55CE16BA, 0x3014, 0x41C1, [0x9C, 0xEB, 0xFA, 0xDE, 0x14, 0x46, 0xAC, 0x6C]);
	static final IID_OWNER_SINK = Com.guid(0x5F20AA40, 0xB57A, 0x4F34, [0x96, 0xAB, 0x35, 0x76, 0xF3, 0x77, 0xCC, 0x79]);

	static function qi(o:Ptr, iid:Ptr):Ptr
		return Arena.scopedValue(a -> {
			var p:Ptr<Ptr> = a.alloc(8);
			p.value = Ptr.nil();
			IUnknownQi.QueryInterface(o, iid, p) >= 0 ? p.value : Ptr.nil();
		});

	static function main() {
		var w = new UiWindow("WinTextTest", 320, 160);
		var name = signal("ab");
		Render.render(<view padding={12}>
			<field tag="name" host="drawn" value={name} onInput={e -> name(e.text)}/>
		</view>, w.root);
		var step = 0;
		var tsf:Null<Tsf> = null;
		function store():Null<Tsf> {
			var native = @:privateAccess w.window.native;
			return cast @:privateAccess (cast native : helder.os.win32.Win32Window).tsf;
		}
		function session(body:Int->Void) {
			TextSession.body = body;
			Arena.scoped(a -> {
				var h:Ptr<Int32> = a.alloc(4);
				var r = ITfContext.RequestEditSession(tsf.context, @:privateAccess Tsf.clientId, TextSession.make(), 7, h);
				if (r < 0 || h.value < 0) check("RequestEditSession", false, StringTools.hex(r) + " " + StringTools.hex(h.value));
			});
			TextSession.body = null;
		}
		var field:EditableText = null;
		w.onFrame = () -> {
			switch step {
				case 0:
					field = cast w.root.find("name");
					w.ui.setFocus(field);
					step = 1;
				case 1:
					step = 2;
				case 2:
					tsf = store();
					check("TSF's store made for the focused field", tsf != null && tsf.advised());
					if (tsf == null) {
						w.close();
						return;
					}
					check("the store's document: the field's text and caret", @:privateAccess tsf.doc == "ab" && @:privateAccess tsf.selStart == 2,
						@:privateAccess tsf.doc + " " + @:privateAccess tsf.selStart);
					session(ec -> {
						var ins = qi(tsf.context, IID_INSERT);
						Arena.scoped(a -> {
							var r:Ptr<Ptr> = a.alloc(8);
							r.value = Ptr.nil();
							ITfInsertAtSelection.InsertTextAtSelection(ins, ec, 0, a.wstring("c"), 1, r);
							Com.release(r.value);
						});
						Com.release(ins);
					});
					check("an input method's insertion typed into the field", field.text == "abc" && name() == "abc", field.text + " " + name());
					step = 3;
				case 3:
					var sink = qi(tsf.block, IID_OWNER_SINK);
					session(ec -> {
						Arena.scoped(a -> {
							var ok:Ptr<Int32> = a.alloc(4);
							IOwner.OnStartComposition(sink, TextView.make(), ok);
						});
						var ins = qi(tsf.context, IID_INSERT);
						Arena.scoped(a -> {
							var r:Ptr<Ptr> = a.alloc(8);
							r.value = Ptr.nil();
							ITfInsertAtSelection.InsertTextAtSelection(ins, ec, 0x80000000, a.wstring("にほ"), 2, r);
							Com.release(r.value);
						});
						Com.release(ins);
						TextView.start = 3;
						TextView.length = 2;
					});
					check("the composition shown in the field, not in its text", field.composition == "にほ" && field.text == "abc", field.composition + " " + field.text);
					session(ec -> IOwner.OnEndComposition(sink, TextView.make()));
					Com.release(sink);
					check("committed: typed, the composition gone", field.composition == "" && field.text == "abcにほ" && name() == "abcにほ", field.composition + " " + field.text);
					step = 4;
				case 4:
					// (the next frame: the field's text told to the store)
					check("the store's document after the commit", @:privateAccess tsf.doc == "abcにほ" && @:privateAccess tsf.selStart == 5, @:privateAccess tsf.doc);
					w.ui.setFocus(null);
					step = 5;
				case 5:
					check("the focus gone: the store's document emptied", @:privateAccess tsf.doc == "", @:privateAccess tsf.doc);
					w.close();
				case _:
			}
			w.ui.requestFrame();
		};
		UiWindow.run();
		Sys.println('WinTextTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 && checks >= 7 ? 0 : 1);
	}
}

class TextSession {
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

class TextView {
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
			for (i in 3...27)
				r[i] = Callback.addr(stub);
			r[25] = Callback.addr(getExtent);
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
class IOwner {
	@:slot(3) static function OnStartComposition(self:Ptr, view:Ptr, ok:Ptr<Int32>):Int;
	@:slot(5) static function OnEndComposition(self:Ptr, view:Ptr):Int;
}
