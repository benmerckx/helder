package studio;

import helder.syntax.Document;
import helder.syntax.Edits;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;
import studio.Theme.c;

// The layers of the design frame zoomed into: its elements as written (the
// markup's tree, <note>s left out), a row each, indented by depth; a click
// selects its node (shift: with the selection), a row dragged up or down
// moves its element among its siblings (helder.syntax's Edits.move: one
// transaction, the markup's order the drawing's), the frame drawn again.
class Layers implements Markup {
	public static function view(studio:Studio):View {
		// (the row dragged and by how far, stage points)
		var moving:Signal<Null<{key:String, dy:Float}>> = signal(null);
		return <view tag="layers" slot="section" max-height="45%" shrink={0} padding="10 6 6" transition="fade" motion="snappy"
			onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<view:button tag="layers-toggle" slot="section-head" padding="2 6 6" role="button" label={studio.layersOpen() ? "Hide the layers" : "Show the layers"}
				cursor="pointer" onPress={() -> studio.layersOpen(!studio.layersOpen.peek())}>
				<image src={Icons.layers} width={12} height={12}/><text grow={1}>Layers</text>
				<image src={studio.layersOpen() ? Icons.chevronDown : Icons.chevronRight} width={12} height={12}/>
			</view:button>
			<Show when={studio.layersOpen()}><scroll min-height={0}>
				<For each={rows(studio)} by={(r:Row) -> r.key}>{(r:Read<Row>) ->
					<view tag={"layer-" + r().key} slot="nav-item" role="button" label={r().label} height={Theme.LAYER} padding={'0 8 0 ${8 + r().depth * 14}'}
						data-on={r().on ? "true" : "false"} transform={offset(moving, r().key)} instant
						onClick={e -> select(studio, r(), e.mods & Key.MOD_SHIFT != 0)}
						onPan={g -> {
							var row = r();
							if (g.state == Ended || g.state == Cancelled) {
								moving(null);
								if (g.state == Ended) reorder(studio, row, Math.round(g.ty / Theme.LAYER));
							} else moving({key: row.key, dy: g.ty});
						}}>
						<image src={r().icon} width={Theme.ICON_S} height={Theme.ICON_S} color={r().on ? c("accent-ink") : c("fg3")}/>
						<text max-lines={1} text-overflow="ellipsis">{r().label}</text>
					</view>
				}</For>
			</scroll></Show>
		</view>;
	}

	static function offset(moving:Signal<Null<{key:String, dy:Float}>>, key:String):String {
		var m = moving();
		return m == null || m.key != key ? "none" : 'translate(0px, ${Math.round(m.dy)}px)';
	}

	// the focused design frame's elements, each a row (its key: its path of indices)
	static function rows(studio:Studio):Array<Row> {
		var f = studio.focused(), sel = studio.selection(), others = studio.others();
		studio.docs.version();
		var info = f == null ? null : studio.project.screen(f);
		if (info == null || info.start == null) return [];
		var doc = studio.docs.get(info.file).doc;
		var frame = doc.elementAt(info.start);
		if (frame == null) return [];
		var out:Array<Row> = [];
		function add(el:Element, key:String, depth:Int) {
			var on = sel != null && sel.screen == f && (sel.start == el.start || Lambda.exists(others, o -> o.start == el.start));
			out.push({key: key, label: label(el), depth: depth, start: el.start, on: on, screen: info.name, icon: icon(el, depth)});
			var k = 0;
			for (c in el.elements())
				if (c.name != "note") add(c, key + "-" + k++, depth + 1);
		}
		add(frame, "0", 0);
		return out;
	}

	// (an element's icon: the frame's, text's, an image's, a box's)
	static function icon(el:Element, depth:Int):helder.ui.Svg
		return depth == 0 ? Icons.frame : el.name == "text" ? Icons.font : el.name == "image" ? Icons.image : el.name.charAt(0) == el.name.charAt(0).toUpperCase() ? Icons.component : Icons.element;

	// (an element's name, its text when it holds a run of it)
	static function label(el:Element):String {
		var t = Studio.textRun(el);
		return el.name + (t == null ? "" : "  " + t.text);
	}

	static function select(studio:Studio, r:Row, add:Bool) {
		var info = studio.project.screen(r.screen);
		var n = studio.designs.nodeAt(r.screen, r.start);
		if (info == null || n == null) return;
		studio.selectDesign(info, n, r.start, add);
	}

	// a row's element dropped by rows from its own (down when positive):
	// moved among its siblings to the one whose row is the last at or above
	// the drop (its first, above them all), selected
	static function reorder(studio:Studio, r:Row, by:Int) {
		var info = studio.project.screen(r.screen);
		if (info == null || by == 0) return;
		var doc = studio.docs.get(info.file).doc;
		var el = doc.elementAt(r.start), parent = el?.parent();
		if (el == null || parent == null || el.start == info.start) return;
		var sibs = [for (e in parent.elements()) if (e.name != "note") e];
		var k = Lambda.findIndex(sibs, e -> e.start == el.start);
		var all = rows(studio);
		var row = Lambda.findIndex(all, x -> x.start == r.start) + by;
		var t = 0;
		for (j in 0...sibs.length)
			if (Lambda.findIndex(all, x -> x.start == sibs[j].start) <= row) t = j;
		if (k < 0 || t == k) return;
		var kids = parent.children();
		var index = Lambda.findIndex(kids, n -> n.start == sibs[t].start) + (t > k ? 1 : 0);
		var tx = try Edits.move(doc, el, parent, index) catch (e:Dynamic) {
			studio.message('layers: $e');
			return;
		}
		// (where the element is after: the start of its text in what was inserted)
		var source = el.source(), at = -1;
		for (c in tx.changes) {
			var i = c.text.indexOf(source);
			if (i >= 0) at = tx.map(c.start, -1) + i;
		}
		studio.edit(info.file, tx, "layer moved", "canvas");
		studio.endGesture();
		studio.log("reordered", {screen: info.name, from: k, to: t, element: el.name});
		if (at >= 0) studio.selectDesign(info, null, at);
	}
}

// (a layer's row: its key, what it says, how deep, its element's offset, whether it is selected)
@:structInit class Row {
	public final key:String;
	public final label:String;
	public final depth:Int;
	public final start:Int;
	public final on:Bool;
	public final screen:String;
	public final icon:helder.ui.Svg;
}
