// An attribute's value is "text" or {expr}.
// expect: MarkupAttribute.hx:6: characters 22-23
// expect: markup: an attribute value
class MarkupAttribute implements hxmc.view.Markup {
	static function main() {
		var e = <div class=main/>;
	}
}
