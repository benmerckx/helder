// The JavaScript side of hxmc.os in the browser: the imports of the module
// "hxmc_os" (src/hxmc/os/web/Dom.hx) for Window, App and Event on a canvas
// (hxmc.os.web.CanvasWindow). Loaded by browser.mjs (its `canvas` option: the
// canvas of the first window, an element or its id).
//
// A canvas's drawing buffer follows its displayed size in device pixels,
// checked before each frame (a Resize event when it changes); a canvas the
// page does not size is given the window's size in CSS pixels. Events are
// queued as they come and polled at the start of the next frame, as the
// native loops poll theirs: keys (as X11 KeySyms, Event.key) once the canvas
// has the focus (a click gives it), the mouse over the canvas in buffer
// pixels from the top left.

// EventKind (src/hxmc/os/Event.hx)
const RESIZE = 2, KEY_DOWN = 3, KEY_UP = 4, MOUSE_MOVE = 5, MOUSE_DOWN = 6, MOUSE_UP = 7;

// KeyboardEvent.key to an X11 KeySym: Latin-1 characters are their
// (unshifted) code, the others from this table
const KEYS = {
	Escape: 0xff1b, Enter: 0xff0d, Tab: 0xff09, Backspace: 0xff08, Delete: 0xffff, Insert: 0xff63, Home: 0xff50, End: 0xff57,
	PageUp: 0xff55, PageDown: 0xff56, ArrowLeft: 0xff51, ArrowUp: 0xff52, ArrowRight: 0xff53, ArrowDown: 0xff54,
	Shift: 0xffe1, Control: 0xffe3, Alt: 0xffe9, Meta: 0xffe7, CapsLock: 0xffe5,
};
for (let i = 1; i <= 12; i++) KEYS['F' + i] = 0xffbd + i;

function keysym(e) {
	if (KEYS[e.key]) return KEYS[e.key];
	if (e.key.length === 1) {
		const c = e.key.toLowerCase().charCodeAt(0);
		if (c < 256) return c;
	}
	return 0;
}

export default function (host) {
	const queue = [];
	const windows = new Set();
	let first = true;

	function push(ev) {
		// (moves between two frames: the last one)
		const last = queue[queue.length - 1];
		if (ev[1] === MOUSE_MOVE && last && last[1] === MOUSE_MOVE && last[0] === ev[0]) queue[queue.length - 1] = ev;
		else queue.push(ev);
	}

	function sync(h) {
		const c = host.handles.get(h);
		const w = Math.round(c.clientWidth * devicePixelRatio), hh = Math.round(c.clientHeight * devicePixelRatio);
		if (w > 0 && hh > 0 && (w !== c.width || hh !== c.height)) {
			c.width = w;
			c.height = hh;
			return true;
		}
		return false;
	}

	function listen(c, h) {
		const pos = (e) => [Math.round(e.offsetX * c.width / Math.max(1, c.clientWidth)), Math.round(e.offsetY * c.height / Math.max(1, c.clientHeight))];
		const off = new AbortController();
		const on = (type, f, o = {}) => c.addEventListener(type, f, { ...o, signal: off.signal });
		on('keydown', (e) => push([h, KEY_DOWN, keysym(e), 0, 0, 0]));
		on('keyup', (e) => push([h, KEY_UP, keysym(e), 0, 0, 0]));
		on('mousemove', (e) => push([h, MOUSE_MOVE, 0, ...pos(e), 0]));
		on('mousedown', (e) => {
			c.focus();
			push([h, MOUSE_DOWN, 0, ...pos(e), e.button + 1]);
		});
		on('mouseup', (e) => push([h, MOUSE_UP, 0, ...pos(e), e.button + 1]));
		on('wheel', (e) => {
			const b = e.deltaY < 0 ? 4 : 5;
			push([h, MOUSE_DOWN, 0, ...pos(e), b]);
			push([h, MOUSE_UP, 0, ...pos(e), b]);
		}, { passive: true });
		on('contextmenu', (e) => e.preventDefault());
		return off;
	}

	const hxmc_os = {
		window_open(title, width, height) {
			const given = first && host.options.canvas;
			first = false;
			let c = typeof given === 'string' ? document.getElementById(given) : given;
			const made = !c;
			if (made) {
				c = document.createElement('canvas');
				c.setAttribute('aria-label', host.string(title));
				document.body.appendChild(c);
			}
			const cs = getComputedStyle(c);
			// (a canvas the page does not size: its size as attributes would grow with the buffer)
			if (made || (!c.style.width && cs.width === c.width + 'px' && cs.height === c.height + 'px')) {
				c.style.width = width + 'px';
				c.style.height = height + 'px';
			}
			c.width = Math.round(width * devicePixelRatio);
			c.height = Math.round(height * devicePixelRatio);
			if (c.tabIndex < 0) c.tabIndex = 0;
			const h = host.handles.add(c);
			sync(h);
			c.hxmcOff = listen(c, h);
			c.hxmcMade = made;
			windows.add(h);
			return h;
		},
		window_close(h) {
			const c = host.handles.get(h);
			c.hxmcOff.abort();
			if (c.hxmcMade) c.remove();
			windows.delete(h);
			host.handles.remove(h);
		},
		canvas(id) {
			const c = document.getElementById(host.string(id));
			return c instanceof HTMLCanvasElement ? host.handles.add(c) : 0;
		},
		width: (h) => host.handles.get(h).width,
		height: (h) => host.handles.get(h).height,
		scale: () => devicePixelRatio,
		next_event(p) {
			const ev = queue.shift();
			if (!ev) return 0;
			new Int32Array(host.memory().buffer, p, 6).set(ev);
			return 1;
		},
		start(frame) {
			const tick = () => {
				for (const h of windows) if (sync(h)) push([h, RESIZE, 0, host.handles.get(h).width, host.handles.get(h).height, 0]);
				if (host.call(frame)) requestAnimationFrame(tick);
			};
			requestAnimationFrame(tick);
		},
	};
	return { hxmc_os };
}
