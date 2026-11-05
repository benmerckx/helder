// The JavaScript side of helder.ui in the browser, loaded by
// src/helder/os/browser.mjs (run's imports: 'ui/imports.mjs' beside os, gfx
// and text's): the imports of the module "hxmc_ui"
// (src/helder/ui/draw/WebAccess.hx), the accessibility tree's adapter.
//
// A UiWindow's accessibility tree (helder.ui.access.AccessTree) is mirrored
// as elements inside its canvas: a canvas's children are its fallback
// content, not drawn but in the page's accessibility tree, focusable, and
// their events reach the canvas's listeners by bubbling. Each node is a
// div with its ARIA role, name and states, its children in order; the
// node with the keyboard focus gets the page's focus (keys still reach the
// program). An activation (a screen reader's click) or a focus moved by
// assistive technology comes back as an action (AccessAction). While a
// text field has it and the window takes text (helder.os's text input: its
// textarea focused, for input methods), the focus stays the textarea's,
// named as the field.
//
// A window's native text editors (src/helder/ui/platform/WebViews.hx): an input
// or a textarea of the page, in a layer over the canvas (its size, clipping
// them), absolutely placed where the
// field's content box is laid out, borderless and transparent (the drawn
// box is the theme's), in the field's font and colour. Edits, focus and the
// keys it leaves to the program (Tab, Escape; Enter, Up and Down on one
// line) are queued for the module.
export default function (host) {
	const editors = new Map();
	const editorEvents = [];
	let nextEditor = 1;
	// a canvas's layer of editors: over it in the page, its size, clipping
	// them (one placed for an older layout never widens the page), kept on
	// the canvas as it changes size
	function layer(c) {
		if (c.hxmcEditors) return c.hxmcEditors;
		const l = document.createElement('div');
		l.style.cssText = 'position:absolute;overflow:hidden;pointer-events:none;z-index:1;';
		document.body.appendChild(l);
		const fit = () => {
			const r = c.getBoundingClientRect();
			l.style.left = r.left + window.scrollX + 'px';
			l.style.top = r.top + window.scrollY + 'px';
			l.style.width = r.width + 'px';
			l.style.height = r.height + 'px';
		};
		fit();
		new ResizeObserver(fit).observe(c);
		l.fit = fit;
		c.hxmcEditors = l;
		return l;
	}
	// (an editor's event: queued, and a frame asked for, which polls it)
	const queue = (ev) => {
		editorEvents.push(ev);
		host.os?.redraw();
	};
	const EDITOR_KEYS = { Tab: 0xff09, Escape: 0xff1b, Enter: 0xff0d, ArrowUp: 0xff52, ArrowDown: 0xff54 };
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
		else if (n.role === 'textbox' || ((n.role === 'combobox' || n.role === 'spinbutton') && n.value !== undefined)) {
			set('aria-label', n.name || null);
			set('aria-multiline', n.multiline ? 'true' : null);
		} else set('aria-label', n.name || null);
		set('aria-description', n.description);
		set('data-href', n.href);
		set('aria-checked', n.checked);
		set('aria-selected', n.selected);
		set('aria-multiselectable', n.multiselectable ? 'true' : null);
		set('aria-current', n.current ? 'page' : null);
		set('aria-live', n.live);
		set('aria-expanded', n.expanded);
		set('aria-level', n.level);
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
			const input = c.hxmcInput;
			const inside = document.activeElement === c || c.contains(document.activeElement) || (input && document.activeElement === input);
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
				const want = (n.role === 'textbox' || n.role === 'combobox' || n.role === 'spinbutton') && n.value ? [document.createTextNode(n.value), ...kids] : kids;
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
				const role = f ? f.getAttribute('role') : null;
				const typed = f && (role === 'textbox' || ((role === 'combobox' || role === 'spinbutton') && f.hxmcValue !== undefined));
				if (f && input && document.activeElement === input && typed) {
					input.setAttribute('aria-label', f.getAttribute('aria-label') ?? '');
					// (a combobox or spin button typed in: the textarea is one, with its states)
					const copy = (k) => (f.hasAttribute(k) ? input.setAttribute(k, f.getAttribute(k)) : input.removeAttribute(k));
					if (role === 'textbox') input.removeAttribute('role');
					else input.setAttribute('role', role);
					for (const k of ['aria-expanded', 'aria-valuenow', 'aria-valuemin', 'aria-valuemax', 'aria-valuetext']) copy(k);
					if (f.getAttribute('aria-multiline')) input.setAttribute('aria-multiline', 'true');
					else input.removeAttribute('aria-multiline');
				} else if (f && document.activeElement !== f) f.focus({ preventScroll: true });
				else if (!f && document.activeElement !== c) c.focus({ preventScroll: true });
				focusing = false;
			}
		},
		// a native text editor over the canvas: its handle
		editor_create(canvas, multiline) {
			const c = host.handles.get(canvas);
			const e = document.createElement(multiline ? 'textarea' : 'input');
			const h = nextEditor++;
			if (!multiline) e.type = 'text';
			e.id = 'hxmc-editor-' + h;
			e.setAttribute('data-hxmc-editor', '');
			e.style.cssText = 'position:absolute;display:none;margin:0;border:0;padding:0;background:transparent;outline:none;box-sizing:border-box;resize:none;overflow:hidden;pointer-events:auto;';
			const style = document.createElement('style');
			document.head.appendChild(style);
			layer(c).appendChild(e);
			const ed = { e, c, style, multiline, focusing: false };
			editors.set(h, ed);
			const mods = (ev) => (ev.shiftKey ? 1 : 0) | (ev.ctrlKey ? 2 : 0) | (ev.altKey ? 4 : 0) | (ev.metaKey ? 8 : 0);
			e.addEventListener('input', () => queue([h, 1, e.selectionStart ?? 0, e.selectionEnd ?? 0, host.handles.add(e.value)]));
			e.addEventListener('focus', () => ed.focusing || queue([h, 2, 0, 0, 0]));
			e.addEventListener('blur', () => ed.focusing || queue([h, 3, 0, 0, 0]));
			e.addEventListener('keydown', (ev) => {
				const k = EDITOR_KEYS[ev.key];
				if (!k || ev.isComposing || (multiline && k !== 0xff09 && k !== 0xff1b)) return;
				ev.preventDefault();
				queue([h, 4, k, mods(ev), 0]);
			});
			return h;
		},
		editor_text(h, text, start, end) {
			const ed = editors.get(h);
			ed.e.value = host.string(text);
			if (document.activeElement === ed.e) ed.e.setSelectionRange(start, end);
		},
		// its place: the window's pixels (the canvas's buffer over its pixel
		// ratio: the device's, at most run's option maxPixelRatio, as os's),
		// scaled as the canvas is shown (a page may show it smaller), in the
		// canvas's layer
		editor_place(h, x, y, w, hh, shown) {
			const ed = editors.get(h), r = ed.c.getBoundingClientRect();
			const ratio = Math.min(devicePixelRatio, host.options.maxPixelRatio ?? Infinity);
			const k = r.width / Math.max(1, Math.round(ed.c.width / ratio));
			const s = ed.e.style;
			layer(ed.c).fit();
			s.display = shown ? '' : 'none';
			s.left = x * k + 'px';
			s.top = y * k + 'px';
			s.width = w + 'px';
			s.height = hh + 'px';
			s.transformOrigin = '0 0';
			s.transform = Math.abs(k - 1) < 1e-3 ? '' : 'scale(' + k + ')';
		},
		editor_style(h, css, placeholder, placeholderColor, secret) {
			const ed = editors.get(h);
			ed.e.style.cssText = ed.e.style.cssText.replace(/(font|line-height|color|text-align):[^;]*;/g, '') + host.string(css);
			ed.e.placeholder = host.string(placeholder);
			ed.style.textContent = '#' + ed.e.id + '::placeholder{color:' + host.string(placeholderColor) + ';opacity:1}';
			if (!ed.multiline) ed.e.type = secret ? 'password' : 'text';
		},
		// the page's focus given, or taken back for the canvas
		editor_focus(h, on) {
			const ed = editors.get(h);
			ed.focusing = true;
			if (on) ed.e.focus({ preventScroll: true });
			else if (document.activeElement === ed.e) ed.c.focus({ preventScroll: true });
			ed.focusing = false;
		},
		editor_dispose(h) {
			const ed = editors.get(h);
			if (!ed) return;
			if (document.activeElement === ed.e) ed.c.focus({ preventScroll: true });
			ed.e.remove();
			ed.style.remove();
			editors.delete(h);
		},
		// the next event into p (five Int32: the handle, the kind, its values); 0: none
		editor_event(p) {
			const ev = editorEvents.shift();
			if (!ev) return 0;
			new Int32Array(host.memory().buffer, p, 5).set(ev);
			return 1;
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
