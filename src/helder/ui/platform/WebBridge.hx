package helder.ui.platform;

// The page's side of a web view's bridge: `window.helder`, put in every
// page before its own scripts (Apple: a WKUserScript at the document's
// start; Android: in the HTML its WebContent serves, and evaluated at each
// page's start for other pages):
//
//   helder.post("text");                  // a string
//   helder.post({kind: "save", n: 1});    // JSON
//   helder.post(new Uint8Array([1, 2]));  // bytes (an ArrayBuffer, a typed array)
//   helder.onmessage = e => use(e.data);  // what native posts (WebView.post, postJson, postBytes)
//   helder.addEventListener("message", e => ...);
//   helder.platform                       // "ios", "macos", "android"
//
// On the wire a message is a string: its kind's letter, then its body
// (s text, j JSON, b base64; c a console line, Apple's console.* sent
// along). Native to the page: an evaluated helder.__receive(kind, body),
// and bytes fetched by the page from its WebContent's origin
// (/__helder/bytes/<id>: an ArrayBuffer, no base64) where it has one.
class WebBridge {
	// the script, posting through send (a JavaScript expression of a function of a string)
	public static function script(platform:String, send:String, console:Bool):String
		return '(function(){if(window.helder&&window.helder.__native)return;var send=$send;var ls=[];'
			+ 'function enc(m){if(typeof m==="string")return "s"+m;if(m instanceof ArrayBuffer)m=new Uint8Array(m);'
			+ 'if(ArrayBuffer.isView(m)){var b=new Uint8Array(m.buffer,m.byteOffset,m.byteLength),s="";'
			+ 'for(var i=0;i<b.length;i+=32768)s+=String.fromCharCode.apply(null,b.subarray(i,i+32768));return "b"+btoa(s);}'
			+ 'return "j"+JSON.stringify(m);}'
			+ 'function dispatch(d){var e={data:d};if(typeof h.onmessage==="function")h.onmessage(e);ls.slice().forEach(function(f){f(e);});}'
			+ 'var h=window.helder={__native:true,platform:"$platform",'
			+ 'post:function(m){send(enc(m));},onmessage:null,'
			+ 'addEventListener:function(t,f){if(t==="message")ls.push(f);},'
			+ 'removeEventListener:function(t,f){var i=ls.indexOf(f);if(i>=0)ls.splice(i,1);},'
			+ '__receive:function(k,b){if(k==="j")dispatch(JSON.parse(b));else if(k==="b"){var s=atob(b),u=new Uint8Array(s.length);'
			+ 'for(var i=0;i<s.length;i++)u[i]=s.charCodeAt(i);dispatch(u.buffer);}else dispatch(b);},'
			+ '__fetch:function(u){fetch(u).then(function(r){return r.arrayBuffer();}).then(dispatch);}};'
			+ (console ? 'try{["log","info","warn","error"].forEach(function(l){var o=console[l];console[l]=function(){'
				+ 'try{send("c"+l+": "+Array.prototype.map.call(arguments,function(a){return typeof a==="string"?a:(function(){try{return JSON.stringify(a);}catch(e){return String(a);}})();}).join(" "));}catch(e){}'
				+ 'return o.apply(console,arguments);};});'
				+ 'window.addEventListener("error",function(e){send("cerror: "+e.message+" ("+e.filename+":"+e.lineno+")");});'
				+ 'window.addEventListener("unhandledrejection",function(e){send("cerror: unhandled rejection: "+String(e.reason));});}catch(e){}' : '')
			+ '})();';

	// the JavaScript delivering a message of kind ("s", "j", "b") to the page
	public static function receive(kind:String, body:String):String
		return 'window.helder&&window.helder.__receive("$kind",' + quote(body) + ');';

	// the JavaScript fetching bytes at url into the page's handlers
	public static function fetch(url:String):String
		return 'window.helder&&window.helder.__fetch(' + quote(url) + ');';

	// a JavaScript string literal of s
	public static function quote(s:String):String {
		var b = new StringBuf();
		b.add('"');
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			switch c {
				case '"'.code: b.add('\\"');
				case '\\'.code: b.add('\\\\');
				case '\n'.code: b.add('\\n');
				case '\r'.code: b.add('\\r');
				case '<'.code: b.add('\\u003c');
				case 0x2028: b.add('\\u2028');
				case 0x2029: b.add('\\u2029');
				case c if (c < 32): b.add('\\u' + StringTools.hex(c, 4));
				case _: b.addChar(c);
			}
		}
		b.add('"');
		return b.toString();
	}

	// an HTML document with the script first in its head (Android's served pages)
	public static function inject(html:String, script:String):String {
		var tag = '<script>' + script + '</script>';
		var lower = html.toLowerCase();
		var at = lower.indexOf("<head");
		if (at >= 0) {
			var end = lower.indexOf(">", at);
			if (end >= 0) return html.substr(0, end + 1) + tag + html.substr(end + 1);
		}
		at = lower.indexOf("<html");
		if (at >= 0) {
			var end = lower.indexOf(">", at);
			if (end >= 0) return html.substr(0, end + 1) + tag + html.substr(end + 1);
		}
		// (no head: after a doctype, else first)
		at = lower.indexOf("<!doctype");
		if (at >= 0) {
			var end = lower.indexOf(">", at);
			if (end >= 0) return html.substr(0, end + 1) + tag + html.substr(end + 1);
		}
		return tag + html;
	}
}
