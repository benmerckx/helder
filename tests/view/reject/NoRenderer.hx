// Content is mounted into a renderer's node: its class names the renderer
// (@:rendered); a String names none.
// expect: NoRenderer.hx:7: characters
// expect: helder.view: String is no renderer's node
class NoRenderer implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<div/>, "root");
	}
}
