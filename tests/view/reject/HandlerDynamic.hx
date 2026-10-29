// A handler of no static type (Dynamic) is an error: a function of no
// event called with one, or a value that is no function, would fail when
// the event comes (natively: a crash), not where it is written.
// expect: HandlerDynamic.hx:9: characters 42-52
// expect: markup: onClick's handler is of no static type (Dynamic): a function of a TestEvent or of none
class HandlerDynamic implements helder.view.Markup {
	static function main() {
		var h:Dynamic = () -> trace("x");
		helder.view.Render.render(<div><button onClick={h}/></div>, new TestRenderer.TestNode(Element, "root"));
	}
}
