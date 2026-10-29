// A renderer's own element's handler is checked against the events it
// declares (TestRenderer's @:events: TestEvents), at the attribute.
// expect: HandlerElement.hx:8: characters 42-68
// expect: markup: onClick's handler takes an Int, but TestRenderer gives onClick a TestEvent: a function of a TestEvent or of none (TestEvent -> Void, or Void -> Void)
class HandlerElement implements helder.view.Markup {
	static function main() {
		var n = 0;
		helder.view.Render.render(<div><button onClick={(k:Int) -> n += k}/></div>, new TestRenderer.TestNode(Element, "root"));
	}
}
