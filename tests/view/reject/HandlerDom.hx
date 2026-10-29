// target: js
// The DOM's events are lib.dom's (DomEvents): a key's handler taking a
// mouse's event is an error at the attribute.
// expect: HandlerDom.hx:10: characters 11-61
// expect: markup: onKeyDown's handler takes a js.html.MouseEvent, but helder.web.DomRenderer gives onKeyDown a js.html.KeyboardEvent
class HandlerDom implements helder.view.Markup {
	static function main() {
		var x = 0.0;
		helder.web.DomRenderer.render(<div>
			<input onKeyDown={(e:js.html.MouseEvent) -> x = e.clientX}/>
		</div>, js.Browser.document.body);
	}
}
