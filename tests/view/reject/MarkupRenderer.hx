// A component of a class limited to other renderers, with none for this
// one, is an error naming it and the renderer.
// expect: MarkupRenderer.hx:14: characters
// expect: OnlyOther.Badge has no version for TestRenderer
@:renderer(OtherRenderer)
class OnlyOther implements helder.view.Markup {
	public static function Badge(props:{label:String}):helder.view.View
		return <badge>{props.label}</badge>;
}

class MarkupRenderer implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<div>
			<OnlyOther.Badge label="a"/>
		</div>, new TestRenderer.TestNode(Element, "root"));
	}
}
