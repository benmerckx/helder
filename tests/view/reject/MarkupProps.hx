// A component's props are checked against its argument, at the attribute.
// expect: MarkupProps.hx:9: characters
// expect: Int should be String
class MarkupProps implements helder.view.Markup {
	static function Label(props:{text:String}):helder.view.View
		return <span>{props.text}</span>;

	static function main() {
		var e = <div><Label text={42}/></div>;
	}
}
