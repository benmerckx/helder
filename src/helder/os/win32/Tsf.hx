package helder.os.win32;

import helder.os.Event;
import helder.os.win32.User32;
import helder.os.win32.FileOpenDialog.Shell32Com;
import helder.os.win32.Com.IUnknown;
import hxmc.unsafe.*;

// Windows' Text Services Framework for a window's drawn text fields: the
// thread's ITfThreadMgr (activated once), and per window a document manager
// with one context whose text store is made here, a COM object of two
// interfaces in one block (ITextStoreACP and ITfContextOwnerCompositionSink,
// each a vtable pointer then the block's address; the block ends with the
// reference count), their methods @:hxmc.callback functions. The store's
// document is the focused field's text and selection (Window.textContext);
// an input method (a TIP: Japanese, Chinese, Korean, the touch keyboard)
// edits it under the store's locks (RequestLock: granted at once, a request
// during one queued until it ends), and after each lock what changed is
// told as the window's events: the text outside the composition that
// differs from the field's as TextInput (an insertion at the caret) or
// TextReplace (anything else), the composition's text (its range the
// composition view's, ITfRangeACP) as TextEditing, ended by a TextEditing
// of nothing. GetTextExt answers with the caret's rectangle (the candidate
// window goes below it), GetScreenExt with the client area. A field's
// change from the program's side (typed through WM_CHAR, a click) is told
// to TSF (OnTextChange, OnSelectionChange) when no lock or composition is
// on. A program that gives no text context (a game taking characters) has
// an empty document, emptied again after each commit. Where TSF is not
// there (CoCreateInstance fails) Win32Window keeps IMM32's own windows.
@:allow(helder.os.win32)
@:hxmc.unsafe(gc)
class Tsf {
	static inline var S_OK = 0;
	static inline var E_NOINTERFACE = 0x80004002;
	static inline var E_NOTIMPL = 0x80004001;
	static inline var E_INVALIDARG = 0x80070057;
	static inline var E_UNEXPECTED = 0x8000FFFF;
	static inline var TS_E_INVALIDPOS = 0x80040200;
	static inline var TS_E_NOLOCK = 0x80040201;
	static inline var TS_E_NOLAYOUT = 0x80040206;
	static inline var TS_E_INVALIDPOINT = 0x80040207;
	static inline var TS_E_SYNCHRONOUS = 0x80040208;
	static inline var TS_S_ASYNC = 0x00040300;
	static inline var CONNECT_E_ADVISELIMIT = 0x80040201;
	static inline var TS_LF_SYNC = 1;
	static inline var TS_LF_READ = 2;
	static inline var TS_LF_READWRITE = 6;
	static inline var TS_IAS_QUERYONLY = 2;
	static inline var TS_SS_NOHIDDENTEXT = 8;
	static inline var TS_AS_TEXT_CHANGE = 1;
	static inline var TS_AS_SEL_CHANGE = 2;
	static inline var TS_AS_LAYOUT_CHANGE = 4;

	static inline var IID_UNKNOWN = "00000000-0000-0000-c000-000000000046";
	static inline var IID_STORE = "28888fe3-c2a0-483a-a3ea-8cb1ce51ff3d";
	static inline var IID_OWNER_SINK = "5f20aa40-b57a-4f34-96ab-3576f377cc79";
	static final CLSID_THREAD_MGR = Com.guid(0x529A9E6B, 0x6587, 0x4F23, [0xAB, 0x9E, 0x9C, 0x7D, 0x68, 0x3E, 0x3C, 0x50]);
	static final IID_THREAD_MGR = Com.guid(0xAA80E801, 0x2021, 0x11D2, [0x93, 0xE0, 0x00, 0x60, 0xB0, 0x67, 0xB8, 0x6E]);
	static final IID_STORE_SINK = Com.guid(0x22D44C94, 0xA419, 0x4542, [0xA2, 0x72, 0xAE, 0x26, 0x09, 0x3E, 0xCE, 0xCF]);
	static final IID_RANGE_ACP = Com.guid(0x057A6296, 0x029B, 0x4154, [0xB7, 0x9A, 0x0D, 0x46, 0x1D, 0x4E, 0xA9, 0x4C]);
	static final IID_OWNER_SERVICES = Com.guid(0x86462810, 0x593B, 0x4916, [0x97, 0x64, 0x19, 0xC0, 0x8E, 0x9C, 0xE1, 0x10]);

	static inline var SLOTS = 2;
	static inline var BLOCK = 16 * SLOTS + 8;

	// the thread's manager (null: not tried yet; nil: TSF not there), its client id
	static var threadMgr:Null<Ptr> = null;
	static var clientId = 0;
	static var vtables:Array<Ptr> = [];
	static final byBlock = new Map<String, Tsf>();

	// the thread's TSF, activated (false: not there, IMM32 then)
	public static function available():Bool {
		if (threadMgr == null) {
			threadMgr = Ptr.nil();
			if (Sys.getEnv("HELDER_NO_TSF") != null && Sys.getEnv("HELDER_NO_TSF") != "") return false;
			Shell32Com.CoInitializeEx(Ptr.nil(), 2); // (COINIT_APARTMENTTHREADED; already: S_FALSE)
			var m = out(p -> Shell32Com.CoCreateInstance(CLSID_THREAD_MGR, Ptr.nil(), 1, IID_THREAD_MGR, p));
			if (m.isNull()) return false;
			var id:Ptr<Int32> = LibC.malloc(4);
			var hr = ITfThreadMgr.Activate(m, id);
			clientId = id.value;
			LibC.free(cast id);
			if (hr < 0) {
				Com.release(m);
				return false;
			}
			threadMgr = m;
			makeVtables();
		}
		return !threadMgr.isNull();
	}

	// (a COM call's out pointer: its value, nil when it failed)
	static function out(f:Ptr<Ptr>->Int):Ptr {
		var p:Ptr<Ptr> = LibC.malloc(8);
		p.value = Ptr.nil();
		var hr = f(p);
		var v = p.value;
		LibC.free(cast p);
		return hr < 0 ? Ptr.nil() : v;
	}

	static function makeVtables() {
		var unknown = [Callback.addr(queryInterface), Callback.addr(addRef), Callback.addr(release)];
		var methods:Array<Array<Ptr>> = [
			[
				Callback.addr(adviseSink), Callback.addr(unadviseSink), Callback.addr(requestLock), Callback.addr(getStatus), Callback.addr(queryInsert),
				Callback.addr(getSelection), Callback.addr(setSelection), Callback.addr(getText), Callback.addr(setText), Callback.addr(notImpl3),
				Callback.addr(notImpl4), Callback.addr(queryInsertEmbedded), Callback.addr(notImpl5), Callback.addr(insertTextAtSelection),
				Callback.addr(notImpl5), Callback.addr(requestAttrs), Callback.addr(requestAttrsAt), Callback.addr(requestAttrsAt),
				Callback.addr(findNextAttrTransition), Callback.addr(retrieveRequestedAttrs), Callback.addr(getEndACP), Callback.addr(getActiveView),
				Callback.addr(getACPFromPoint), Callback.addr(getTextExt), Callback.addr(getScreenExt), Callback.addr(getWnd)
			],
			[Callback.addr(onStartComposition), Callback.addr(onUpdateComposition), Callback.addr(onEndComposition)]
		];
		for (m in methods) {
			var all = unknown.concat(m);
			var t:Ptr<Ptr> = LibC.malloc(8 * all.length);
			for (i in 0...all.length)
				t[i] = all[i];
			vtables.push(t);
		}
	}

	final hwnd:Ptr;
	// a window event: kind, text, x, y
	final emit:(EventKind, String, Int, Int) -> Void;
	public final block:Ptr;
	public var docMgr(default, null) = Ptr.nil();
	public var context(default, null) = Ptr.nil();
	var emptyMgr = Ptr.nil();
	var sink = Ptr.nil();
	var sinkMask = 0;

	// the document (UTF-16) and its selection; the active end (TS_AE_START 1, TS_AE_END 2)
	var doc = "";
	var selStart = 0;
	var selEnd = 0;
	var activeEnd = 2;
	// the field's text and selection as the program has it (told or expected)
	var ctx = "";
	var ctxStart = 0;
	var ctxEnd = 0;
	var hasContext = false;
	// the lock held (TS_LF_READ, TS_LF_READWRITE; 0: none), and one asked for during it
	var lock = 0;
	var queued = 0;
	// the composition: on, its view (referenced), its range as the edits made it (when the view gives none)
	var composing = false;
	var view = Ptr.nil();
	var compStart = 0;
	var compEnd = 0;
	// the composition told last, its caret
	var told = "";
	var toldCaret = 0;
	// the caret's rectangle (client pixels; width 0: none yet)
	var areaX = 0;
	var areaY = 0;
	var areaW = 0;
	var areaH = 0;
	var focused = false;
	// (nothing told: a composition ended as the field loses the focus)
	var muted = false;

	public function new(hwnd:Ptr, emit:(EventKind, String, Int, Int) -> Void) {
		this.hwnd = hwnd;
		this.emit = emit;
		block = LibC.malloc(BLOCK);
		for (k in 0...SLOTS) {
			(block.add(16 * k) : Ptr<Ptr>).value = vtables[k];
			(block.add(16 * k + 8) : Ptr<Ptr>).value = block;
		}
		(block.add(16 * SLOTS) : Ptr<Int64>).value = 1;
		byBlock.set(key(block), this);
		var m = threadMgr;
		docMgr = out(p -> ITfThreadMgr.CreateDocumentMgr(m, p));
		emptyMgr = out(p -> ITfThreadMgr.CreateDocumentMgr(m, p));
		if (docMgr.isNull()) return;
		var cookie:Ptr<Int32> = LibC.malloc(4);
		var d = docMgr;
		context = out(p -> ITfDocumentMgr.CreateContext(d, clientId, 0, block, p, cookie));
		LibC.free(cast cookie);
		// (pushed: TSF advises the store's sink)
		if (!context.isNull()) ITfDocumentMgr.Push(docMgr, context);
	}

	public function dispose() {
		focus(false);
		if (!docMgr.isNull()) {
			ITfDocumentMgr.Pop(docMgr, 1); // (TF_POPF_ALL)
			Com.release(context);
			Com.release(docMgr);
			context = docMgr = Ptr.nil();
		}
		Com.release(emptyMgr);
		emptyMgr = Ptr.nil();
		Com.release(sink);
		sink = Ptr.nil();
		releaseBlock(block);
	}

	// whether the store's sink is there (TSF took the context)
	public function advised():Bool
		return !sink.isNull();

	// text input on at the caret (client pixels), or off: the document
	// manager the window's focus (TSF's input methods edit the store), or
	// the empty one (none do), a composition ended first
	public function area(x:Int, y:Int, w:Int, h:Int) {
		var moved = x != areaX || y != areaY || w != areaW || h != areaH;
		areaX = x;
		areaY = y;
		areaW = w;
		areaH = h;
		focus(true);
		if (moved && lock == 0 && !sink.isNull() && sinkMask & TS_AS_LAYOUT_CHANGE != 0) ITextStoreACPSink.OnLayoutChange(sink, 1, 1); // (TS_LC_CHANGE)
	}

	public function focus(on:Bool) {
		if (on == focused || threadMgr == null || threadMgr.isNull()) return;
		focused = on;
		var m = threadMgr;
		if (!on) {
			// (the input method asked to end it, its commit not told: the
			// field has gone, and dropped its composition)
			muted = true;
			if (composing && !context.isNull()) {
				var c = context;
				var s = out(p -> IUnknownQi.QueryInterface(c, IID_OWNER_SERVICES, p));
				if (!s.isNull()) {
					ITfContextOwnerCompositionServices.TerminateComposition(s, Ptr.nil());
					Com.release(s);
				}
			}
			if (composing) endComposition();
			muted = false;
			told = "";
			toldCaret = 0;
			Com.release(out(p -> ITfThreadMgr.AssociateFocus(m, hwnd, Ptr.nil(), p)));
			if (!emptyMgr.isNull()) ITfThreadMgr.SetFocus(m, emptyMgr);
			ctx = "";
			ctxStart = ctxEnd = 0;
			reset("", 0, 0);
			hasContext = false;
		} else {
			var d = docMgr;
			Com.release(out(p -> ITfThreadMgr.AssociateFocus(m, hwnd, d, p)));
			if (!d.isNull()) ITfThreadMgr.SetFocus(m, d);
		}
	}

	// the field's text and selection (UTF-16 indices), from the program
	public function textContext(text:String, start:Int, end:Int) {
		hasContext = true;
		ctx = text;
		ctxStart = clamp(start, text.length);
		ctxEnd = clamp(end, text.length);
		if (lock != 0 || composing) return;
		reset(text, ctxStart, ctxEnd);
	}

	// the document made this, TSF told
	function reset(text:String, start:Int, end:Int) {
		if (doc == text && selStart == start && selEnd == end) return;
		var old = doc.length, changed = doc != text;
		doc = text;
		selStart = start < end ? start : end;
		selEnd = start < end ? end : start;
		activeEnd = 2;
		if (sink.isNull() || lock != 0) return;
		if (changed && sinkMask & TS_AS_TEXT_CHANGE != 0)
			Arena.scoped(a -> {
				var c:Ptr<Int32> = a.alloc(12);
				c[0] = 0;
				c[1] = old;
				c[2] = text.length;
				ITextStoreACPSink.OnTextChange(sink, 0, c);
			});
		if (sinkMask & TS_AS_SEL_CHANGE != 0) ITextStoreACPSink.OnSelectionChange(sink);
	}

	static inline function clamp(i:Int, n:Int):Int
		return i < 0 ? 0 : i > n ? n : i;

	// the composition's range now: its view's (ITfRangeACP), else the edits'
	function compositionRange():{start:Int, end:Int} {
		if (!view.isNull()) {
			var v = view;
			var r = out(p -> ITfCompositionView.GetRange(v, p));
			if (!r.isNull()) {
				var acp = out(p -> IUnknownQi.QueryInterface(r, IID_RANGE_ACP, p));
				Com.release(r);
				if (!acp.isNull()) {
					var got = Arena.scopedValue(a -> {
						var anchor:Ptr<Int32> = a.alloc(4), n:Ptr<Int32> = a.alloc(4);
						if (ITfRangeACP.GetExtent(acp, anchor, n) >= 0) {
							var s = clamp(anchor.value, doc.length);
							{start: s, end: clamp(s + n.value, doc.length)};
						} else null;
					});
					Com.release(acp);
					if (got != null) {
						compStart = got.start;
						compEnd = got.end;
					}
				}
			}
		}
		compStart = clamp(compStart, doc.length);
		compEnd = clamp(compEnd, doc.length);
		if (compEnd < compStart) compEnd = compStart;
		return {start: compStart, end: compEnd};
	}

	// (the composition over: its text stays in the document, told as committed)
	function endComposition() {
		if (!composing) return;
		compositionRange();
		composing = false;
		Com.release(view);
		view = Ptr.nil();
	}

	// what the locks changed, told: the field's text outside the composition, the composition
	function flush() {
		if (muted) return;
		var base = doc, comp = "", caret = 0;
		if (composing) {
			var r = compositionRange();
			base = doc.substr(0, r.start) + doc.substr(r.end);
			comp = doc.substring(r.start, r.end);
			caret = clamp(selEnd - r.start, comp.length);
		}
		// (a composition gone first, then its commit)
		if (comp == "" && told != "") {
			told = "";
			toldCaret = 0;
			emit(TextEditing, "", 0, 0);
		}
		if (base != ctx) {
			// (the change: what differs between the common start, kept at
			// most to the caret, and the common end)
			var p = 0, n = ctx.length, m = base.length;
			var most = ctxStart < n ? ctxStart : n;
			while (p < most && p < m && StringTools.fastCodeAt(ctx, p) == StringTools.fastCodeAt(base, p))
				p++;
			var q = 0;
			while (q < n - p && q < m - p && StringTools.fastCodeAt(ctx, n - 1 - q) == StringTools.fastCodeAt(base, m - 1 - q))
				q++;
			var a = p, b = n - q, ins = base.substring(p, m - q);
			if ((a == ctxStart && b == ctxEnd) || !hasContext && a == b) {
				if (ins != "") emit(TextInput, ins, 0, 0) else if (a != b) emit(TextReplace, "", a, b);
			} else emit(TextReplace, ins, a, b);
			ctx = base;
			ctxStart = ctxEnd = a + ins.length;
		}
		if (comp != told || caret != toldCaret) {
			told = comp;
			toldCaret = caret;
			if (comp != "") emit(TextEditing, comp, caret, 0);
		}
		// (no field's text: emptied after each commit)
		if (!composing && !hasContext && doc != "") {
			ctx = "";
			ctxStart = ctxEnd = 0;
			reset("", 0, 0);
		}
	}

	// s over start...end of the document (the composition's range follows)
	function replace(start:Int, end:Int, s:String) {
		doc = doc.substr(0, start) + s + doc.substr(end);
		if (composing) {
			var delta = s.length - (end - start);
			var e = compEnd >= end ? compEnd + delta : compEnd > start ? start + s.length : compEnd;
			if (start < compStart) compStart = start;
			compEnd = e > start + s.length ? e : start + s.length;
		}
	}

	static function wide(p:Ptr<UInt16>, n:Int):String {
		var b = new StringBuf(), i = 0;
		while (i < n) {
			var c:Int = p[i++];
			if (c >= 0xD800 && c < 0xDC00 && i < n && p[i] >= 0xDC00 && p[i] < 0xE000) c = 0x10000 + ((c - 0xD800) << 10) + ((p[i++] : Int) - 0xDC00);
			b.addChar(c);
		}
		return b.toString();
	}

	static inline function key(b:Ptr):String
		return Std.string(b.toI64());

	static inline function base(self:Ptr):Ptr
		return (self.add(8) : Ptr<Ptr>).value;

	static function of(self:Ptr):Null<Tsf>
		return byBlock.get(key(base(self)));

	static function releaseBlock(b:Ptr):Int {
		var refs:Ptr<Int64> = b.add(16 * SLOTS);
		var n = refs.value.toInt() - 1;
		refs.value = n;
		if (n == 0) {
			byBlock.remove(key(b));
			LibC.free(b);
		}
		return n;
	}

	// --- IUnknown ---

	@:hxmc.callback static function queryInterface(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int {
		if (out.isNull()) return E_INVALIDARG;
		out.value = Ptr.nil();
		var g = Com.iid(iid), b = base(self);
		var k = g == IID_UNKNOWN || g == IID_STORE ? 0 : g == IID_OWNER_SINK ? 1 : -1;
		if (k < 0) return E_NOINTERFACE;
		var refs:Ptr<Int64> = b.add(16 * SLOTS);
		refs.value = refs.value.toInt() + 1;
		out.value = b.add(16 * k);
		return S_OK;
	}

	@:hxmc.callback static function addRef(self:Ptr):Int {
		var refs:Ptr<Int64> = base(self).add(16 * SLOTS);
		var n = refs.value.toInt() + 1;
		refs.value = n;
		return n;
	}

	@:hxmc.callback static function release(self:Ptr):Int
		return releaseBlock(base(self));

	// --- ITextStoreACP ---

	@:hxmc.callback static function adviseSink(self:Ptr, iid:Ptr, punk:Ptr, mask:Int):Int {
		var t = of(self);
		if (t == null || punk.isNull()) return E_INVALIDARG;
		var s = out(p -> IUnknownQi.QueryInterface(punk, IID_STORE_SINK, p));
		if (s.isNull()) return E_INVALIDARG;
		if (!t.sink.isNull()) {
			var same = t.sink == s;
			Com.release(s);
			if (!same) return CONNECT_E_ADVISELIMIT;
			t.sinkMask = mask;
			return S_OK;
		}
		t.sink = s;
		t.sinkMask = mask;
		return S_OK;
	}

	@:hxmc.callback static function unadviseSink(self:Ptr, punk:Ptr):Int {
		var t = of(self);
		if (t == null) return E_INVALIDARG;
		Com.release(t.sink);
		t.sink = Ptr.nil();
		t.sinkMask = 0;
		return S_OK;
	}

	@:hxmc.callback static function requestLock(self:Ptr, flags:Int, hr:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null || t.sink.isNull()) return E_UNEXPECTED;
		if (hr.isNull()) return E_INVALIDARG;
		if (t.lock != 0) {
			// (one at a time: a synchronous one refused, an asynchronous one after this)
			if (flags & TS_LF_SYNC != 0) {
				hr.value = TS_E_SYNCHRONOUS;
				return S_OK;
			}
			t.queued |= flags & TS_LF_READWRITE;
			hr.value = TS_S_ASYNC;
			return S_OK;
		}
		t.lock = flags & TS_LF_READWRITE;
		if (t.lock == 0) t.lock = TS_LF_READ;
		hr.value = ITextStoreACPSink.OnLockGranted(t.sink, t.lock);
		t.lock = 0;
		while (t.queued != 0 && !t.sink.isNull()) {
			t.lock = t.queued;
			t.queued = 0;
			ITextStoreACPSink.OnLockGranted(t.sink, t.lock);
			t.lock = 0;
		}
		t.flush();
		return S_OK;
	}

	@:hxmc.callback static function getStatus(self:Ptr, s:Ptr<Int32>):Int {
		if (s.isNull()) return E_INVALIDARG;
		s[0] = 0;
		s[1] = TS_SS_NOHIDDENTEXT;
		return S_OK;
	}

	@:hxmc.callback static function queryInsert(self:Ptr, start:Int, end:Int, n:Int, rs:Ptr<Int32>, re:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null || start < 0 || start > end || end > t.doc.length) return E_INVALIDARG;
		if (!rs.isNull()) rs.value = start;
		if (!re.isNull()) re.value = end;
		return S_OK;
	}

	@:hxmc.callback static function getSelection(self:Ptr, index:Int, count:Int, sel:Ptr<Int32>, fetched:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null || fetched.isNull()) return E_INVALIDARG;
		fetched.value = 0;
		if (t.lock == 0) return TS_E_NOLOCK;
		// (one selection: TS_DEFAULT_SELECTION or the first)
		if (index != 0 && index != -1) return E_INVALIDARG;
		if (count == 0 || sel.isNull()) return S_OK;
		sel[0] = t.selStart;
		sel[1] = t.selEnd;
		sel[2] = t.activeEnd;
		sel[3] = 0;
		fetched.value = 1;
		return S_OK;
	}

	@:hxmc.callback static function setSelection(self:Ptr, count:Int, sel:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null || sel.isNull()) return E_INVALIDARG;
		if (t.lock != TS_LF_READWRITE) return TS_E_NOLOCK;
		if (count < 1) return E_INVALIDARG;
		var a = sel[0], b = sel[1];
		if (a < 0 || b < a || b > t.doc.length) return TS_E_INVALIDPOS;
		t.selStart = a;
		t.selEnd = b;
		t.activeEnd = sel[2] == 1 ? 1 : 2;
		return S_OK;
	}

	@:hxmc.callback static function getText(self:Ptr, start:Int, end:Int, plain:Ptr<UInt16>, want:Int, got:Ptr<Int32>, runs:Ptr<Int32>, wantRuns:Int,
			gotRuns:Ptr<Int32>, next:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null) return E_INVALIDARG;
		if (!got.isNull()) got.value = 0;
		if (!gotRuns.isNull()) gotRuns.value = 0;
		if (t.lock == 0) return TS_E_NOLOCK;
		var len = t.doc.length;
		if (end == -1) end = len;
		if (start < 0 || start > len || end < start || end > len) return TS_E_INVALIDPOS;
		var n = end - start;
		if (n > want) n = want < 0 ? 0 : want;
		if (!plain.isNull())
			for (i in 0...n)
				plain[i] = StringTools.fastCodeAt(t.doc, start + i);
		if (!got.isNull()) got.value = n;
		if (wantRuns > 0 && !runs.isNull() && n > 0) {
			runs[0] = n;
			runs[1] = 0; // TS_RT_PLAIN
			if (!gotRuns.isNull()) gotRuns.value = 1;
		}
		if (!next.isNull()) next.value = start + n;
		return S_OK;
	}

	@:hxmc.callback static function setText(self:Ptr, flags:Int, start:Int, end:Int, text:Ptr<UInt16>, n:Int, change:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null) return E_INVALIDARG;
		if (t.lock != TS_LF_READWRITE) return TS_E_NOLOCK;
		var len = t.doc.length;
		if (start < 0 || start > len || end < start || end > len) return TS_E_INVALIDPOS;
		var s = text.isNull() ? "" : wide(text, n);
		t.replace(start, end, s);
		// (the caret after it, as Chromium's store has it)
		t.selStart = t.selEnd = start + n;
		if (!change.isNull()) {
			change[0] = start;
			change[1] = end;
			change[2] = start + n;
		}
		return S_OK;
	}

	@:hxmc.callback static function insertTextAtSelection(self:Ptr, flags:Int, text:Ptr<UInt16>, n:Int, ps:Ptr<Int32>, pe:Ptr<Int32>, change:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null) return E_INVALIDARG;
		var a = t.selStart, b = t.selEnd;
		if (flags & TS_IAS_QUERYONLY != 0) {
			if (t.lock == 0) return TS_E_NOLOCK;
			if (!ps.isNull()) ps.value = a;
			if (!pe.isNull()) pe.value = b;
			return S_OK;
		}
		if (t.lock != TS_LF_READWRITE) return TS_E_NOLOCK;
		var s = text.isNull() ? "" : wide(text, n);
		t.replace(a, b, s);
		t.selStart = t.selEnd = a + n;
		if (!ps.isNull()) ps.value = a;
		if (!pe.isNull()) pe.value = a + n;
		if (!change.isNull()) {
			change[0] = a;
			change[1] = b;
			change[2] = a + n;
		}
		return S_OK;
	}

	// (GetFormattedText; GetEmbedded; InsertEmbedded and InsertEmbeddedAtSelection: no embedded objects)
	@:hxmc.callback static function notImpl3(self:Ptr, a:Int, b:Int, c:Ptr):Int
		return E_NOTIMPL;

	@:hxmc.callback static function notImpl4(self:Ptr, a:Int, b:Ptr, c:Ptr, d:Ptr):Int
		return E_NOTIMPL;

	@:hxmc.callback static function notImpl5(self:Ptr, a:Int, b:Ptr, c:Ptr, d:Ptr, e:Ptr):Int
		return E_NOTIMPL;

	@:hxmc.callback static function queryInsertEmbedded(self:Ptr, service:Ptr, format:Ptr, ok:Ptr<Int32>):Int {
		if (!ok.isNull()) ok.value = 0;
		return S_OK;
	}

	// (no attributes: none supported, none to retrieve)
	@:hxmc.callback static function requestAttrs(self:Ptr, flags:Int, n:Int, attrs:Ptr):Int
		return S_OK;

	@:hxmc.callback static function requestAttrsAt(self:Ptr, pos:Int, n:Int, attrs:Ptr, flags:Int):Int
		return S_OK;

	@:hxmc.callback static function findNextAttrTransition(self:Ptr, start:Int, halt:Int, n:Int, attrs:Ptr, flags:Int, next:Ptr<Int32>, found:Ptr<Int32>,
			offset:Ptr<Int32>):Int {
		if (!next.isNull()) next.value = halt;
		if (!found.isNull()) found.value = 0;
		if (!offset.isNull()) offset.value = 0;
		return S_OK;
	}

	@:hxmc.callback static function retrieveRequestedAttrs(self:Ptr, n:Int, vals:Ptr, fetched:Ptr<Int32>):Int {
		if (!fetched.isNull()) fetched.value = 0;
		return S_OK;
	}

	@:hxmc.callback static function getEndACP(self:Ptr, acp:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null || acp.isNull()) return E_INVALIDARG;
		if (t.lock == 0) return TS_E_NOLOCK;
		acp.value = t.doc.length;
		return S_OK;
	}

	@:hxmc.callback static function getActiveView(self:Ptr, v:Ptr<Int32>):Int {
		if (v.isNull()) return E_INVALIDARG;
		v.value = 1;
		return S_OK;
	}

	@:hxmc.callback static function getACPFromPoint(self:Ptr, v:Int, pt:Ptr, flags:Int, acp:Ptr<Int32>):Int
		return TS_E_INVALIDPOINT;

	// (the caret's rectangle on the screen, for any range: the candidates below it)
	@:hxmc.callback static function getTextExt(self:Ptr, v:Int, start:Int, end:Int, rc:Ptr<Int32>, clipped:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null || rc.isNull()) return E_INVALIDARG;
		if (t.lock == 0) return TS_E_NOLOCK;
		if (t.areaH <= 0) return TS_E_NOLAYOUT;
		var o = t.origin();
		rc[0] = o.x + t.areaX;
		rc[1] = o.y + t.areaY;
		rc[2] = o.x + t.areaX + (t.areaW > 0 ? t.areaW : 1);
		rc[3] = o.y + t.areaY + t.areaH;
		if (!clipped.isNull()) clipped.value = 0;
		return S_OK;
	}

	@:hxmc.callback static function getScreenExt(self:Ptr, v:Int, rc:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null || rc.isNull()) return E_INVALIDARG;
		var o = t.origin();
		Arena.scoped(a -> {
			var r = a.make(RECT);
			User32.GetClientRect(t.hwnd, r);
			rc[0] = o.x;
			rc[1] = o.y;
			rc[2] = o.x + r.value.right;
			rc[3] = o.y + r.value.bottom;
		});
		return S_OK;
	}

	@:hxmc.callback static function getWnd(self:Ptr, v:Int, h:Ptr<Ptr>):Int {
		var t = of(self);
		if (t == null || h.isNull()) return E_INVALIDARG;
		h.value = t.hwnd;
		return S_OK;
	}

	// the client area's top left on the screen
	function origin():{x:Int, y:Int}
		return Arena.scopedValue(a -> {
			var p = a.make(POINT);
			User32.ClientToScreen(hwnd, p);
			{x: p.value.x, y: p.value.y};
		});

	// --- ITfContextOwnerCompositionSink ---

	@:hxmc.callback static function onStartComposition(self:Ptr, v:Ptr, ok:Ptr<Int32>):Int {
		var t = of(self);
		if (t == null) return E_INVALIDARG;
		if (!ok.isNull()) ok.value = 1;
		if (t.composing) t.endComposition();
		t.composing = true;
		if (!v.isNull()) IUnknown.AddRef(v);
		t.view = v;
		t.compStart = t.selStart;
		t.compEnd = t.selEnd;
		return S_OK;
	}

	@:hxmc.callback static function onUpdateComposition(self:Ptr, v:Ptr, range:Ptr):Int
		return S_OK;

	@:hxmc.callback static function onEndComposition(self:Ptr, v:Ptr):Int {
		var t = of(self);
		if (t == null) return E_INVALIDARG;
		t.endComposition();
		if (t.lock == 0) t.flush();
		return S_OK;
	}
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class IUnknownQi {
	@:slot(0) static function QueryInterface(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ITfThreadMgr {
	@:slot(3) static function Activate(self:Ptr, id:Ptr<Int32>):Int;
	@:slot(4) static function Deactivate(self:Ptr):Int;
	@:slot(5) static function CreateDocumentMgr(self:Ptr, out:Ptr<Ptr>):Int;
	@:slot(8) static function SetFocus(self:Ptr, dm:Ptr):Int;
	@:slot(9) static function AssociateFocus(self:Ptr, hwnd:Ptr, dm:Ptr, prev:Ptr<Ptr>):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ITfDocumentMgr {
	@:slot(3) static function CreateContext(self:Ptr, client:Int, flags:Int, punk:Ptr, out:Ptr<Ptr>, cookie:Ptr<Int32>):Int;
	@:slot(4) static function Push(self:Ptr, context:Ptr):Int;
	@:slot(5) static function Pop(self:Ptr, flags:Int):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ITextStoreACPSink {
	@:slot(3) static function OnTextChange(self:Ptr, flags:Int, change:Ptr<Int32>):Int;
	@:slot(4) static function OnSelectionChange(self:Ptr):Int;
	@:slot(5) static function OnLayoutChange(self:Ptr, code:Int, view:Int):Int;
	@:slot(8) static function OnLockGranted(self:Ptr, flags:Int):Int;
}

@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ITfCompositionView {
	@:slot(4) static function GetRange(self:Ptr, out:Ptr<Ptr>):Int;
}

// (ITfRange's 22 methods after IUnknown, then ITfRangeACP's)
@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ITfRangeACP {
	@:slot(25) static function GetExtent(self:Ptr, anchor:Ptr<Int32>, n:Ptr<Int32>):Int;
}

// (ITfContextComposition's four methods after IUnknown, then TerminateComposition)
@:build(helder.os.win32.Com.build())
@:hxmc.unsafe(gc)
class ITfContextOwnerCompositionServices {
	@:slot(7) static function TerminateComposition(self:Ptr, view:Ptr):Int;
}
