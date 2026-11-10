import helder.asset.Asset;
import helder.ui.Svg;

// Lucide's icons (examples/foundry/icons, ISC: LICENSE), those used
class Icons {
	public static final pen = load(Asset.embed("icons/pen-tool.svg"));
	public static final pointer = load(Asset.embed("icons/mouse-pointer-2.svg"));
	public static final eraser = load(Asset.embed("icons/eraser.svg"));
	public static final undo = load(Asset.embed("icons/undo-2.svg"));
	public static final redo = load(Asset.embed("icons/redo-2.svg"));
	public static final eye = load(Asset.embed("icons/eye.svg"));
	public static final download = load(Asset.embed("icons/download.svg"));
	public static final trash = load(Asset.embed("icons/trash-2.svg"));
	public static final sparkles = load(Asset.embed("icons/sparkles.svg"));
	public static final component = load(Asset.embed("icons/component.svg"));
	public static final scissors = load(Asset.embed("icons/scissors.svg"));

	static function load(b:haxe.io.Bytes):Svg
		return Svg.parse(b.toString());
}
