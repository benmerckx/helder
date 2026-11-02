// A style attribute ui does not have is an error at its name, suggesting the
// one meant (CSS's flex-wrap is wrap here).
// expect: StyleUnknown.hx:7: characters 35-44
// expect: helder.ui: no attribute flex-wrap (not one of NodeRenderer's or Style's); did you mean wrap?
class StyleUnknown implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view flex-wrap="wrap"/>, new helder.ui.Node());
	}
}
