package studio;

import helder.asset.Asset;
import helder.ui.Svg;

// The studio's icons: Lucide's (apps/studio/icons, ISC: LICENSE), only
// those used, embedded; 24 by 24, stroked in the text's colour, drawn at
// 16 or 14 points (Theme.ICON), their strokes Lucide's 2
class Icons {
	public static final appWindow = load(Asset.embed("icons/app-window.svg"));
	public static final audioLines = load(Asset.embed("icons/audio-lines.svg"));
	public static final bookOpen = load(Asset.embed("icons/book-open.svg"));
	public static final model = load(Asset.embed("icons/box.svg"));
	public static final chevronDown = load(Asset.embed("icons/chevron-down.svg"));
	public static final chevronRight = load(Asset.embed("icons/chevron-right.svg"));
	public static final code = load(Asset.embed("icons/code.svg"));
	public static final component = load(Asset.embed("icons/component.svg"));
	public static final file = load(Asset.embed("icons/file.svg"));
	public static final fileCode = load(Asset.embed("icons/file-code.svg"));
	public static final folder = load(Asset.embed("icons/folder.svg"));
	public static final folderOpen = load(Asset.embed("icons/folder-open.svg"));
	public static final frame = load(Asset.embed("icons/frame.svg"));
	public static final globe = load(Asset.embed("icons/globe.svg"));
	public static final image = load(Asset.embed("icons/image.svg"));
	public static final layoutGrid = load(Asset.embed("icons/layout-grid.svg"));
	public static final maximize = load(Asset.embed("icons/maximize.svg"));
	public static final monitor = load(Asset.embed("icons/monitor.svg"));
	public static final penTool = load(Asset.embed("icons/pen-tool.svg"));
	public static final play = load(Asset.embed("icons/play.svg"));
	public static final redo = load(Asset.embed("icons/redo-2.svg"));
	public static final ruler = load(Asset.embed("icons/ruler.svg"));
	public static final scan = load(Asset.embed("icons/scan.svg"));
	public static final search = load(Asset.embed("icons/search.svg"));
	public static final smartphone = load(Asset.embed("icons/smartphone.svg"));
	public static final sparkles = load(Asset.embed("icons/sparkles.svg"));
	public static final element = load(Asset.embed("icons/square.svg"));
	public static final font = load(Asset.embed("icons/type.svg"));
	public static final undo = load(Asset.embed("icons/undo-2.svg"));

	static function load(b:haxe.io.Bytes):Svg
		return Svg.parse(b.toString());
}
