package helder.ui;

// An inset title bar's area free of the window's buttons, in UI pixels:
// markup's env(titlebar-area-x), -y, -width, -height (the Window Controls
// Overlay's names; SafeArea binds them as the safe area's)
class TitlebarArea {
	public final x:Float;
	public final y:Float;
	public final width:Float;
	public final height:Float;

	public function new(x:Float, y:Float, width:Float, height:Float) {
		this.x = x;
		this.y = y;
		this.width = width;
		this.height = height;
	}

	public static function same(a:Null<TitlebarArea>, b:Null<TitlebarArea>):Bool
		return a == null || b == null ? a == b : a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height;
}
