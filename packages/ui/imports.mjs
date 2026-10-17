// The JavaScript side of hxmc.ui in the browser, loaded by
// packages/os/browser.mjs (run's imports: 'ui/imports.mjs' beside os, gfx
// and text's): the imports of the module "hxmc_ui"
// (src/hxmc/ui/draw/WebAccess.hx), the accessibility tree's adapter.
//
// A UiWindow's accessibility tree (hxmc.ui.access.AccessTree) is mirrored
// as elements inside its canvas: a canvas's children are its fallback
// content, not drawn but in the page's accessibility tree, focusable, and
// their events reach the canvas's listeners by bubbling. Each node is a
// div with its ARIA role, name and states, its children in order; the
// node with the keyboard focus gets the page's focus (keys still reach the
// program). An activation (a screen reader's click) or a focus moved by
// assistive technology comes back as an action (AccessAction).
export default function (host) {
	// per canvas: the mirror's root, its elements by node id
	const mirrors = new Map();
	const actions = [];
	// (focus() of ours: not an action)
	let focusing = false;

	function mirror(canvas) {
		let m = mirrors.get(canvas);
		if (!m) {
			const root = document.createElement('div');
			canvas.appendChild(root);
			m = { root, elements: new Map(), rootId: 0 };
			mirrors.set(canvas, m);
		}
		return m;
	}

	function element(m, id) {
		let e = m.elements.get(id);
		if (!e) {
			e = document.createElement('div');
			e.id = 'hxmc-access-' + id;
			e.addEventListener('click', (ev) => {
				actions.push([id, 0]);
				ev.stopPropagation();
			});
			e.addEventListener('focus', () => {
				if (!focusing) actions.push([id, 1]);
			});
			m.elements.set(id, e);
		}
		return e;
	}

	function apply(e, n) {
		const set = (k, v) => (v === undefined || v === null ? e.removeAttribute(k) : e.setAttribute(k, String(v)));
		set('role', n.role === 'text' ? null : n.role);
		if (n.role === 'text') e.textContent = n.name;
		else if (n.role === 'textbox') {
			set('aria-label', n.name || null);
			set('aria-multiline', n.multiline ? 'true' : null);
		} else set('aria-label', n.name || null);
		set('aria-description', n.description);
		set('aria-checked', n.checked);
		set('aria-selected', n.selected);
		set('aria-expanded', n.expanded);
		set('aria-disabled', n.disabled ? 'true' : null);
		set('aria-valuenow', n.valueNow);
		set('aria-valuemin', n.valueMin);
		set('aria-valuemax', n.valueMax);
		set('aria-valuetext', n.valueText);
		set('tabindex', n.focusable ? '-1' : null);
		e.hxmcValue = n.value;
		e.hxmcChildren = n.children;
	}

	const hxmc_ui = {
		// an update of the tree of the window whose canvas is that handle (JSON:
		// full, root, focus, nodes, removed)
		access_update(canvas, json) {
			const c = host.handles.get(canvas);
			const u = JSON.parse(host.string(json));
			const m = mirror(c);
			// (whether the page's focus is the canvas's, before the elements
			// move: moving the focused one would blur it)
			const inside = document.activeElement === c || c.contains(document.activeElement);
			if (u.full) {
				m.elements.clear();
				m.root.replaceChildren();
			}
			for (const id of u.removed) {
				m.elements.get(id)?.remove();
				m.elements.delete(id);
			}
			for (const n of u.nodes) apply(element(m, n.id), n);
			// the children in order (of each node updated: its list is its own)
			for (const n of u.nodes) {
				const e = m.elements.get(n.id);
				const kids = n.children.map((k) => element(m, k));
				// (a textbox's value is its text, before its children)
				const want = n.role === 'textbox' && n.value ? [document.createTextNode(n.value), ...kids] : kids;
				if (n.role === 'text') continue;
				// (only what differs moves: the focused element stays put)
				const have = [...e.childNodes];
				const same = have.length === want.length && want.every((w, i) => w === have[i] || (w.nodeType === 3 && have[i].nodeType === 3 && w.data === have[i].data));
				if (!same) e.replaceChildren(...want);
			}
			m.rootId = u.root;
			const top = m.elements.get(u.root);
			if (top && top.parentNode !== m.root) m.root.replaceChildren(top);
			// the focus: the program's focused node, while the page's focus is the canvas's
			if (inside) {
				const f = u.focus ? m.elements.get(u.focus) : null;
				focusing = true;
				if (f && document.activeElement !== f) f.focus({ preventScroll: true });
				else if (!f && document.activeElement !== c) c.focus({ preventScroll: true });
				focusing = false;
			}
		},
		// the next action into p (two Int32: the node id, the AccessAction); 0: none
		access_action(p) {
			const a = actions.shift();
			if (!a) return 0;
			new Int32Array(host.memory().buffer, p, 2).set(a);
			return 1;
		},
	};
	return { hxmc_ui };
}
