package helder.ui;

// Ui's popups: layers over the tree (children of Ui.overlay), opened and
// closed (the focus taken by a modal one, given back where it was), placed
// by their anchor and kept in the window, dismissed by a press outside them.
@:allow(helder.ui)
@:access(helder.ui.Ui)
class Popups {
	// shows a popup over the tree, above those open; a modal one covers the
	// window (its content centred) and takes the focus (its first focusable node)
	static function open(ui:Ui, p:Popup) {
		if (p.parent == ui.overlay) return;
		p.returnFocus = ui.focus;
		if (p.modal) {
			p.style.left = 0;
			p.style.top = 0;
			p.style.width = DimValue.Percent(100);
			p.style.height = DimValue.Percent(100);
			p.style.alignItems = Center;
			p.style.justify = Center;
		}
		ui.overlay.append(p);
		if (p.modal) {
			var f = firstFocusable(p);
			ui.setFocus(f);
		}
		ui.requestFrame();
	}

	// removes a popup; the focus, if it was inside, goes back to where it was when it opened
	static function close(ui:Ui, p:Popup) {
		if (p.parent != ui.overlay) return;
		var inside = ui.focus != null && Ui.contains(p, ui.focus);
		ui.overlay.remove(p);
		if (inside || ui.focus == null) {
			var r = p.returnFocus;
			ui.setFocus(r != null && r.ui == ui ? r : null);
		}
		p.returnFocus = null;
		ui.requestFrame();
	}

	static function at(ui:Ui, i:Int):Null<Popup> {
		var c = ui.overlay.children[i];
		return Std.isOfType(c, Popup) ? cast c : null;
	}

	// the topmost modal popup (null: none)
	static function modal(ui:Ui):Null<Popup> {
		var i = ui.overlay.children.length;
		while (--i >= 0) {
			var p = at(ui, i);
			if (p != null && p.modal) return p;
		}
		return null;
	}

	static function firstFocusable(n:Node):Null<Node> {
		if (n.style.display == None) return null;
		if (n.focusable && n.visible()) return n;
		for (c in n.children) {
			var f = firstFocusable(c);
			if (f != null) return f;
		}
		return null;
	}

	// a press outside the popups on top (and their anchors) dismisses them;
	// on a modal one's backdrop, it
	static function dismissOutside(ui:Ui, target:Null<Node>) {
		var i = ui.overlay.children.length;
		while (--i >= 0) {
			if (i >= ui.overlay.children.length) continue;
			var p = at(ui, i);
			if (p == null) continue;
			if (target != null && target != p && Ui.contains(p, target)) break;
			if (p.modal) {
				if (target == p && p.onDismiss != null && p.dismissOnOutside) p.onDismiss();
				break;
			}
			if (target != null && p.anchor != null && Ui.contains(p.anchor, target)) break;
			if (p.onDismiss != null && p.dismissOnOutside) p.onDismiss();
		}
	}

	// the anchored popups placed (their style's left and top): true when one moved
	static function place(ui:Ui):Bool {
		var moved = false;
		for (c in ui.overlay.children) {
			if (!Std.isOfType(c, Popup)) continue;
			var p:Popup = cast c;
			if (p.modal || p.placement == Manual) continue;
			var w = p.width, h = p.height, x = 0.0, y = 0.0;
			if (p.placement == Point) {
				x = p.atX + w > ui.width && p.atX - w >= 0 ? p.atX - w : p.atX;
				y = p.atY + h > ui.height && p.atY - h >= 0 ? p.atY - h : p.atY;
			} else if (p.placement == TopLeft || p.placement == TopRight || p.placement == BottomLeft || p.placement == BottomRight) {
				x = p.placement == TopLeft || p.placement == BottomLeft ? p.gap : ui.width - w - p.gap;
				y = p.placement == TopLeft || p.placement == TopRight ? p.gap : ui.height - h - p.gap;
			} else if (p.placement == Center || p.anchor == null || p.anchor.ui != ui) {
				if (p.placement != Center && p.anchor != null) continue;
				x = (ui.width - w) / 2;
				y = (ui.height - h) / 2;
			} else {
				// the anchor where it is drawn: its ancestors' scrolling taken off, through transforms
				var a = p.anchor.windowBounds(), ax = a.x, ay = a.y;
				var g = p.gap;
				switch p.placement {
					case Below | Above:
						// (right to left: their right edges lined up)
						x = p.anchor.rtl() ? ax + a.width - w : ax;
						var below = ay + a.height + g, above = ay - g - h;
						y = p.placement == Below ? (below + h > ui.height && above >= 0 ? above : below) : (above < 0 && below + h <= ui.height ? below : above);
					case _:
						y = ay;
						var right = ax + a.width + g, left = ax - g - w;
						x = p.placement == Right ? (right + w > ui.width && left >= 0 ? left : right) : (left < 0 && right + w <= ui.width ? right : left);
				}
			}
			x = Math.round(Math.max(0, Math.min(x, ui.width - w)));
			y = Math.round(Math.max(0, Math.min(y, ui.height - h)));
			if (p.style.left.resolve(0) != x || p.style.top.resolve(0) != y) {
				p.style.left = x;
				p.style.top = y;
				moved = true;
			}
		}
		return moved;
	}
}
