// Markup needs a renderer (-D helder.view.renderer); // no renderer here.
// expect: helder.view: no renderer
class NoRenderer implements helder.view.Markup {
	static function main() {
		var e = <div/>;
	}
}
