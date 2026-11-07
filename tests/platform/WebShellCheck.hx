import helder.ui.platform.*;

// WebViewCheck's page and checks in a web view on the whole screen
// (WebShell: iOS's WKWebView as its window's root view, Android's WebView
// as the activity's content, org.hxmc.Activity): an app's thin native shell.
//   helder build tests/platform/WebShellCheck.hx --target ios-sim | android-x86_64
class WebShellCheck {
	static function main() {
		WebViewCheck.start("shell");
		WebShell.run({content: WebViewCheck.content, src: "index.html", inspectable: true}, (shell, e) -> {
			WebViewCheck.post = shell.post;
			WebViewCheck.postBytes = shell.postBytes;
			WebViewCheck.load = shell.load;
			WebViewCheck.snapshot = shell.snapshot;
			WebViewCheck.evalJs = shell.eval;
			WebViewCheck.event(e);
		});
	}
}
