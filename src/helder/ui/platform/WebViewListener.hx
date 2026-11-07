package helder.ui.platform;

// What hears a PlatformWebView (WebView, WebShell), on the program's thread
interface WebViewListener {
	function webViewEvent(e:WebViewEvent):Void;
}
