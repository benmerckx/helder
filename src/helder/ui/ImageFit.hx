package helder.ui;

// How an ImageNode's image fills its content box (CSS's object-fit)
enum abstract ImageFit(Int) {
	// stretched to the box
	var Fill;
	// scaled to fit inside it, centred (bars beside or above)
	var Contain;
	// scaled to cover it, centred (cut at the sides or top and bottom)
	var Cover;
	// at its own size, centred (cut where larger)
	var None;
}
