// A prop the component does not take is an error.
// expect: MarkupUnknownProp.hx:9: characters
// expect: has extra field colour
class MarkupUnknownProp implements hxmc.view.Markup {
	static function Label(props:{text:String}):hxmc.view.View
		return <span>{props.text}</span>;

	static function main() {
		var e = <div><Label text="a" colour="red"/></div>;
	}
}
