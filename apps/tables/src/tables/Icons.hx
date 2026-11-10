package tables;

import helder.asset.Asset;
import helder.ui.Svg;

// Lucide's icons (apps/tables/icons, ISC: LICENSE), those used
class Icons {
	public static final table = load(Asset.embed("icons/table-2.svg"));
	public static final view = load(Asset.embed("icons/eye.svg"));
	public static final search = load(Asset.embed("icons/search.svg"));
	public static final plus = load(Asset.embed("icons/plus.svg"));
	public static final trash = load(Asset.embed("icons/trash-2.svg"));
	public static final refresh = load(Asset.embed("icons/refresh-cw.svg"));
	public static final database = load(Asset.embed("icons/database.svg"));
	public static final columns = load(Asset.embed("icons/columns-3.svg"));
	public static final terminal = load(Asset.embed("icons/square-terminal.svg"));
	public static final back = load(Asset.embed("icons/chevron-left.svg"));
	public static final key = load(Asset.embed("icons/key-round.svg"));
	public static final link = load(Asset.embed("icons/link.svg"));
	public static final close = load(Asset.embed("icons/x.svg"));
	public static final open = load(Asset.embed("icons/arrow-up-right.svg"));
	public static final filter = load(Asset.embed("icons/list-filter.svg"));
	public static final play = load(Asset.embed("icons/play.svg"));
	public static final undo = load(Asset.embed("icons/undo-2.svg"));
	public static final panel = load(Asset.embed("icons/panel-right.svg"));
	public static final check = load(Asset.embed("icons/check.svg"));

	static function load(b:haxe.io.Bytes):Svg
		return Svg.parse(b.toString());
}
