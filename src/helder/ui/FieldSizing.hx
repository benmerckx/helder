package helder.ui;

// how a text field is sized where its style gives no size (CSS's
// field-sizing): Fixed by the field (a TextArea's rows), Content by its
// text (a TextArea as tall as its lines, at least one: shadcn's
// field-sizing-content, with min-h-16 for a floor)
enum abstract FieldSizing(Int) {
	var Fixed;
	var Content;
}
