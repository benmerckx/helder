// Haxe's lexer ends a literal at its root's "/>" only while it is in the
// root's opening tag, which a "<" leaves (a comparison or markup in an
// attribute): such a root is closed by its closing tag, <Rows ...></Rows>.
// expect: MarkupSelfClosing.hx:10: character 17
// expect: Unterminated markup literal
class MarkupSelfClosing implements helder.view.Markup {
	static function Rows(props:{count:Int, render:Int->helder.view.View}):helder.view.View
		return <ul>{[for (i in 0...props.count) props.render(i)]}</ul>;

	static var e = <Rows count={2} render={i -> i < 1 ? <b/> : <i/>}/>;
}
