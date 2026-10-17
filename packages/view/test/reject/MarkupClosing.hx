// A closing tag names the element it closes.
// expect: MarkupClosing.hx:6: characters 23-27
// expect: markup: </i> closes <b>
class MarkupClosing implements hxmc.view.Markup {
	static function main() {
		var e = <div><b>bold</i></div>;
	}
}
