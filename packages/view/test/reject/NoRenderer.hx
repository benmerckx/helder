// Markup needs a renderer (-D hxmc.view.renderer); // no renderer here.
// expect: hxmc.view: no renderer
class NoRenderer implements hxmc.view.Markup {
	static function main() {
		var e = <div/>;
	}
}
