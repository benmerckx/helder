// A component pinned to a renderer by its return type (ViewOf<R>, R's node)
// in another renderer's markup is an error at its tag.
// expect: WrongRenderer.hx:11: characters
// expect: helder.view: <Mark> is OtherRenderer's markup (it returns helder.view.ViewOf<OtherRenderer>), not TestRenderer's
class WrongRenderer implements helder.view.Markup {
	static function Mark(props:{}):helder.view.ViewOf<OtherRenderer>
		return <mark/>;

	static function main() {
		helder.view.Render.render(<div>
			<Mark/>
		</div>, new TestRenderer.TestNode(Element, "root"));
	}
}
