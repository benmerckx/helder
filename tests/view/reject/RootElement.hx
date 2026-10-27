// A root (Render.open's, UiWindow.run's) holds components only: an element
// needs a renderer's parent.
// expect: RootElement.hx:7: characters
// expect: markup: <div> needs a renderer's parent
class RootElement implements helder.view.Markup {
	static function main() {
		helder.view.Render.open(<><div/></>);
	}
}
