// The site's demos, full screen: a playing demo's Full screen button puts
// its stage (the island's container) in the Fullscreen API's full screen,
// its canvas filling the screen (CanvasWindow follows the element's size and
// devicePixelRatio: its ResizeObserver), the orientation locked to the
// demo's shape where the browser lets it; where there is no element full
// screen (iPhone's Safari), the stage is expanded instead: fixed over the
// viewport (100dvh), clear of the safe areas, with an Exit button. Either
// way the canvas takes every touch (touch-action: none: the page does not
// scroll under a game), and Escape or the button leaves.
(() => {
	const canFull = () => !!(document.fullscreenEnabled || document.webkitFullscreenEnabled);
	const fullElement = () => document.fullscreenElement || document.webkitFullscreenElement;
	let open = null;

	function touch(stage, on) {
		const c = stage.querySelector('canvas');
		if (!c) return;
		if (on) {
			c.dataset.touchAction = c.style.touchAction;
			c.style.touchAction = 'none';
		} else if (c.dataset.touchAction !== undefined) {
			c.style.touchAction = c.dataset.touchAction;
			delete c.dataset.touchAction;
		}
		// (the game's canvas focused: its keys)
		if (on) c.focus({ preventScroll: true });
	}

	async function enter(stage) {
		if (open) leave();
		open = stage;
		stage.classList.add('expanded');
		document.documentElement.classList.add('playing');
		touch(stage, true);
		if (canFull()) {
			try {
				await (stage.requestFullscreen ? stage.requestFullscreen({ navigationUI: 'hide' }) : stage.webkitRequestFullscreen());
				stage.classList.add('fullscreen');
				const w = +stage.dataset.width, h = +stage.dataset.height;
				// (a phone turned to the demo's shape, where the browser allows it)
				if (screen.orientation && screen.orientation.lock && w && h) screen.orientation.lock(h > w ? 'portrait' : 'landscape').catch(() => {});
			} catch {
				// (refused: expanded over the page instead)
			}
		}
	}

	function leave() {
		const stage = open;
		if (!stage) return;
		open = null;
		stage.classList.remove('expanded', 'fullscreen');
		document.documentElement.classList.remove('playing');
		touch(stage, false);
		if (screen.orientation && screen.orientation.unlock) try { screen.orientation.unlock(); } catch {}
		if (fullElement()) (document.exitFullscreen || document.webkitExitFullscreen).call(document).catch?.(() => {});
		stage.scrollIntoView({ block: 'nearest' });
	}

	for (const ev of ['fullscreenchange', 'webkitfullscreenchange'])
		document.addEventListener(ev, () => {
			// (left by the browser: Escape, the system's back gesture)
			if (open && open.classList.contains('fullscreen') && !fullElement()) leave();
		});
	document.addEventListener('keydown', (e) => {
		if (e.key === 'Escape' && open && !fullElement()) leave();
	});
	document.addEventListener('click', (e) => {
		const b = e.target.closest && e.target.closest('button.full, button.exit');
		if (!b) return;
		e.stopPropagation();
		const stage = b.closest('.stage');
		if (b.classList.contains('exit') || open === stage) leave();
		else enter(stage);
	}, true);
	// (a game's canvas takes every touch on the page too: a drag is its, not the page's scroll; before loader.js reads the options)
	const options = (globalThis.hxmcWasmOptions ||= {});
	for (const s of document.querySelectorAll('.stage[data-game] hxmc-island')) options[s.id] = { ...options[s.id], touchAction: 'none' };
	globalThis.hxmcStage = { enter, leave };
})();
