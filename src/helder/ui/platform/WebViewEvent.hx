package helder.ui.platform;

import haxe.io.Bytes;

enum abstract WebViewEventKind(Int) {
	// the page posted a message (helder.post): text, JSON text, or bytes
	var Message;
	// a navigation began (url)
	var Navigate;
	// the URL shown changed (url: a navigation committed, history.pushState)
	var UrlChange;
	// the page loaded (url)
	var Load;
	// its title changed (text)
	var Title;
	// the load's progress (progress, 0 to 1)
	var Progress;
	// a load failed (url, text: the error, code: the platform's)
	var LoadError;
	// the page logged (text; Android's console.*, Apple's through the bridge)
	var Console;
	// the page's process went (iOS's web content process; Android's renderer): reload it
	var Crash;
}

// A web view's event (WebView's handlers, WebViewListener): what each kind
// has is in WebViewEventKind
class WebViewEvent {
	public final kind:WebViewEventKind;
	public var url = "";
	public var text = "";
	// a message's: the page posted JSON (text; json() parses it)
	public var isJson = false;
	// a message's binary (an ArrayBuffer or a typed array the page posted)
	public var bytes:Null<Bytes> = null;
	public var progress = 0.0;
	public var code = 0;

	public function new(kind:WebViewEventKind)
		this.kind = kind;

	// a message's value: its JSON parsed, else its text
	public function json():Dynamic
		return isJson ? haxe.Json.parse(text) : text;

	// a message from the bridge's wire form (WebBridge: s text, j JSON, b base64, c a console line)
	public static function message(wire:String):WebViewEvent {
		var tag = wire.charAt(0), body = wire.substr(1);
		var e = new WebViewEvent(tag == "c" ? Console : Message);
		switch tag {
			case "j":
				e.isJson = true;
				e.text = body;
			case "b":
				e.bytes = try haxe.crypto.Base64.decode(body) catch (_:Dynamic) Bytes.alloc(0);
			case "s" | "c":
				e.text = body;
			case _:
				e.text = wire;
		}
		return e;
	}
}
