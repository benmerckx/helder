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
// assistive technology comes back as an action (AccessAction). While a
// text field has it and the window takes text (hxmc.os's text input: its
// textarea focused, for input methods), the focus stays the textarea's,
// named as the field.
//
// hxmc.ui.native's DOM backend (src/hxmc/ui/native/dom/DomBackend.hx): a
// container (run's option nativeContainer, an element or its id, else a
// new div) where the page's own controls are placed absolutely at the
// layout's positions: button, a span for a label, input (text, checkbox
// in a label, range), progress. Measured by the browser (their size with
// no size set, text in a span); their events queued for the module, text
// as string handles; frames from requestAnimationFrame.
//
// A window's native text editors (src/hxmc/ui/draw/WebViews.hx): an input
// or a textarea of the page, absolutely placed over the canvas where the
// field's content box is laid out, borderless and transparent (the drawn
// box is the theme's), in the field's font and colour. Edits, focus and the
// keys it leaves to the program (Tab, Escape; Enter, Up and Down on one
// line) are queued for the module.
export default function (host) {
	const editors = new Map();
	const editorEvents = [];
	let nextEditor = 1;
	// (an editor's event: queued, and a frame asked for, which polls it)
	const queue = (ev) => {
		editorEvents.push(ev);
		host.os?.redraw();
	};
	const EDITOR_KEYS = { Tab: 0xff09, Escape: 0xff1b, Enter: 0xff0d, ArrowUp: 0xff52, ArrowDown: 0xff54 };
	const nativeQueue = [];
	let nativeFirst = true;
	const KINDS = ['button', 'label', 'field', 'checkbox', 'slider', 'progress'];
	let measurer = null;
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

	const nat = {
		native_open(title, w, h) {
			const given = nativeFirst && host.options.nativeContainer;
			nativeFirst = false;
			let c = typeof given === 'string' ? document.getElementById(given) : given;
			if (!c) {
				c = document.createElement('div');
				c.setAttribute('aria-label', host.string(title));
				document.body.appendChild(c);
			}
			c.style.position = 'relative';
			if (!c.style.width) c.style.width = w + 'px';
			if (!c.style.height) c.style.height = h + 'px';
			c.style.overflow = 'hidden';
			return host.handles.add(c);
		},
		native_width: (c) => host.handles.get(c).clientWidth,
		native_height: (c) => host.handles.get(c).clientHeight,
		native_create(c, kind) {
			const k = KINDS[kind] ?? 'label';
			let e, input = null;
			switch (k) {
				case 'button': e = document.createElement('button'); break;
				case 'field': e = input = document.createElement('input'); input.type = 'text'; break;
				case 'checkbox':
					e = document.createElement('label');
					input = document.createElement('input');
					input.type = 'checkbox';
					e.append(input, document.createElement('span'));
					break;
				case 'slider': e = input = document.createElement('input'); input.type = 'range'; break;
				case 'progress': e = document.createElement('progress'); e.max = 1; break;
				default: e = document.createElement('span'); e.style.whiteSpace = 'pre-wrap'; e.style.overflowWrap = 'anywhere';
			}
			e.style.position = 'absolute';
			e.style.boxSizing = 'border-box';
			e.style.margin = '0';
			const h = host.handles.add(e);
			e.hxmcInput = input;
			if (k === 'button') e.addEventListener('click', () => nativeQueue.push([h, 0, 0]));
			if (k === 'field') {
				input.addEventListener('input', () => nativeQueue.push([h, 1, host.handles.add(input.value)]));
				input.addEventListener('keydown', (ev) => ev.key === 'Enter' && nativeQueue.push([h, 2, 0]));
			}
			if (k === 'checkbox') input.addEventListener('change', () => nativeQueue.push([h, 3, input.checked ? 1 : 0]));
			if (k === 'slider') input.addEventListener('input', () => nativeQueue.push([h, 4, host.handles.add(input.value)]));
			host.handles.get(c).appendChild(e);
			return h;
		},
		// a control's or label's properties (JSON: text, placeholder, checked, value, min, max, step, enabled; font, color, align)
		native_update(h, json) {
			const e = host.handles.get(h), p = JSON.parse(host.string(json)), i = e.hxmcInput;
			if (p.font) e.style.font = p.font;
			if (p.color) e.style.color = p.color;
			if (p.align) e.style.textAlign = p.align;
			switch (e.tagName) {
				case 'BUTTON': e.textContent = p.text; break;
				case 'SPAN': e.textContent = p.text; break;
				case 'PROGRESS': e.value = p.value; break;
				case 'LABEL': i.checked = p.checked; e.lastChild.textContent = ' ' + p.text; break;
				case 'INPUT':
					if (i.type === 'text') {
						if (i.value !== p.text) i.value = p.text;
						i.placeholder = p.placeholder ?? '';
					} else {
						i.min = p.min;
						i.max = p.max;
						i.step = p.step > 0 ? p.step : 'any';
						i.value = p.value;
					}
			}
			if (p.enabled !== undefined) (i ?? e).disabled = !p.enabled;
		},
		native_place(h, x, y, w, ht) {
			const s = host.handles.get(h).style;
			s.left = x + 'px';
			s.top = y + 'px';
			s.width = w + 'px';
			s.height = ht + 'px';
		},
		native_destroy(h) {
			host.handles.get(h)?.remove();
			host.handles.remove(h);
		},
		// a control's own size (no size set) into p (two Float64)
		native_measure(h, p) {
			const e = host.handles.get(h), s = e.style;
			const w = s.width, ht = s.height;
			s.width = s.height = '';
			const r = e.getBoundingClientRect();
			s.width = w;
			s.height = ht;
			new Float64Array(host.memory().buffer, p, 2).set([r.width, r.height]);
		},
		// text's size in a font (CSS), within maxWidth (negative: none), into p
		native_measure_text(text, font, maxWidth, p) {
			if (!measurer) {
				measurer = document.createElement('span');
				measurer.style.cssText = 'position:absolute;visibility:hidden;left:-10000px;top:0;white-space:pre-wrap;overflow-wrap:anywhere;';
				document.body.appendChild(measurer);
			}
			measurer.style.font = host.string(font);
			measurer.style.width = maxWidth >= 0 ? maxWidth + 'px' : '';
			measurer.style.maxWidth = '';
			measurer.textContent = host.string(text);
			let r = measurer.getBoundingClientRect();
			if (maxWidth >= 0) {
				// (its lines' width, not the box's)
				measurer.style.width = 'max-content';
				measurer.style.maxWidth = maxWidth + 'px';
				r = { width: measurer.getBoundingClientRect().width, height: r.height };
			}
			new Float64Array(host.memory().buffer, p, 2).set([r.width, r.height]);
		},
		// the next event into p (three Int32: the handle, the kind: 0 click,
		// 1 text, 2 submit, 3 toggle, 4 value; its value or string handle)
		native_next(p) {
			const ev = nativeQueue.shift();
			if (!ev) return 0;
			new Int32Array(host.memory().buffer, p, 3).set(ev);
			return 1;
		},
		native_string_length: (h) => new TextEncoder().encode(String(host.handles.get(h))).length,
		native_string_take(h, p) {
			const b = new TextEncoder().encode(String(host.handles.get(h)));
			new Uint8Array(host.memory().buffer, p, b.length).set(b);
			host.handles.remove(h);
		},
		// requestAnimationFrame calls frame (a @:hxmc.callback ():Int) until it returns 0
		native_start(frame) {
			const tick = () => host.call(frame) && requestAnimationFrame(tick);
			requestAnimationFrame(tick);
		},
	};

	const hxmc_ui = {
		...nat,
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
			e.style.cssText = 'position:absolute;display:none;margin:0;border:0;padding:0;background:transparent;outline:none;box-sizing:border-box;resize:none;overflow:hidden;z-index:1;';
			const style = document.createElement('style');
			document.head.appendChild(style);
			document.body.appendChild(e);
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
		// its place: the canvas's CSS pixels, in the page's
		editor_place(h, x, y, w, hh, shown) {
			const ed = editors.get(h), r = ed.c.getBoundingClientRect();
			const s = ed.e.style;
			s.display = shown ? '' : 'none';
			s.left = r.left + window.scrollX + x + 'px';
			s.top = r.top + window.scrollY + y + 'px';
			s.width = w + 'px';
			s.height = hh + 'px';
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
