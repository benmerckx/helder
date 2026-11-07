package helder.ui.platform;

// A system web view (WebView's, a node's; WebShell's, the whole screen):
// WKWebView on iOS and macOS (AppleWebView), android.webkit.WebView on
// Android (AndroidWebView). Its events go to its listener on the program's
// thread when it is polled (WebView: before each layout; WebShell: its loop).
interface PlatformWebView {
	function listen(l:WebViewListener):Void;
	// its place in the window's layout pixels (points); shown false: hidden
	function place(x:Float, y:Float, width:Float, height:Float, shown:Bool):Void;
	// a URL (one of its content's origin: served by its WebContent)
	function load(url:String):Void;
	// an HTML string, at baseUrl (its relative URLs; null: the content's origin, else about:blank)
	function loadHtml(html:String, ?baseUrl:String):Void;
	// JavaScript run in the page (its result unused)
	function eval(js:String):Void;
	function goBack():Void;
	function goForward():Void;
	function reload():Void;
	function stop():Void;
	// a still of what it shows (null: none could be made)
	function snapshot(done:Null<WebSnapshot>->Void):Void;
	// the events since the last poll, handed to the listener
	function poll():Void;
	function dispose():Void;
}

// What a web view is made with (WebView's, WebShell's)
typedef WebViewOptions = {
	// its own origin's files (WebContent: a scheme handler); null: none
	?content:WebContent,
	// the web inspector (Safari's Develop menu, chrome://inspect); by
	// default in debug builds (helder dev, -D helder.inspectable)
	?inspectable:Bool,
	// pinch and double-tap zoom (false, the default: an app's page at its own scale)
	?zoom:Bool,
	// its background transparent until the page draws (what is behind it shows)
	?transparent:Bool,
	// the back gesture (iOS: a swipe from the edge; Android: the Back key) going back in its history (true)
	?backGesture:Bool
}

// A still of a page: its size in pixels and its RGBA8 pixels (straight alpha)
typedef WebSnapshot = {width:Int, height:Int, pixels:haxe.io.Bytes};
