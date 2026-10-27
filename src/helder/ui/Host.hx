package helder.ui;

// What draws a widget (docs/plans/native-or-drawn.md): Native, the
// platform's own control (Ui.platform's: in a browser a DOM element) placed
// where its node is laid out; Drawn, helder.ui's renderer; Auto (Node.host's
// default) takes the nearest ancestor's that is not Auto, else what the
// window's policy (Ui.policy) says for that kind of widget. Native where a
// platform has no such control is Drawn.
enum abstract Host(Int) to Int {
	var Auto;
	var Native;
	var Drawn;

	// (markup's host="native": a name, any case)
	@:from public static function fromString(s:String):Host
		return switch s == null ? "" : s.toLowerCase() {
			case "native": Native;
			case "drawn": Drawn;
			case _: Auto;
		}
}
