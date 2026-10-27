// A root (a component returning RootView: <Surface>) in a renderer's
// markup is an error at its tag.
// expect: RootInMarkup.hx:15: characters
// expect: helder.view: <Window> is a root (it returns helder.view.RootView): UiWindow.run's or Render.open's content, not TestRenderer's markup
class RootInMarkup implements helder.view.Markup {
	static function Window(props:{}):helder.view.RootView
		return null;

	static function main() {
		helder.view.Render.render(<div>
			<p/>
			<p/>
			<p/>
			<p/>
			<Window/>
		</div>, new TestRenderer.TestNode(Element, "root"));
	}
}
