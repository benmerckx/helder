package helder.ui.access;

// whether assistive technology announces a region's changes (ARIA's
// aria-live): Polite when the user is idle, Assertive at once
enum abstract Live(Int) to Int {
	var Off;
	var Polite;
	var Assertive;

	public function aria():Null<String>
		return switch (cast this : Live) {
			case Polite: "polite";
			case Assertive: "assertive";
			case _: null;
		}
}
