// helder.web's <Surface> (a page's: the DOM's, static HTML's) in ui's
// markup is an error naming it and the renderer (ui's is UiWindow.Surface).
// expect: WebSurfaceInUi.hx:8: characters
// expect: WebTags.Surface has no version for helder.ui.view.NodeRenderer
class WebSurfaceInUi implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view>
			<helder.web.WebTags.Surface src="app.wasm"/>
		</view>, new helder.ui.Node());
	}
}
