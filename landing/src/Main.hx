import Compiler;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;

// The landing page (main.js): the universe (a planet per example, Universe)
// and its worlds (World: an example compiled in this tab by the resident
// compiler in a worker, run on the stage, edited live). #/<example id>
// opens a world.
class Main {
	static var world:World;
	static var universe:Universe;
	static var client:CompilerClient;
	static var examples:Array<Example>;

	static inline function byId(id:String):Element
		return document.getElementById(id);

	public static function toast(html:String) {
		var t = document.createDivElement();
		t.className = "toast";
		t.innerHTML = html;
		byId("toasts").append(t);
		haxe.Timer.delay(() -> t.remove(), 3300);
	}

	static function main() {
		var sky = new Sky(cast byId("sky"));
		var forge = new Forge(sky);
		client = new CompilerClient();
		client.onState = (state, text) -> {
			var core = byId("core");
			core.classList.toggle("loading", state == "loading");
			core.classList.toggle("ready", state == "ready");
			byId("core-state").textContent = text;
		}
		window.fetch("manifest.json").then(r -> r.json()).then((manifest:Manifest) -> {
			examples = manifest.examples;
			byId("version").textContent = ~/^.*nightly\./.replace(manifest.hxmc.version, "");
			universe = new Universe(examples, sky);
			world = new World(manifest, client, sky, forge, universe);
			universe.onEnter = e -> go(e);
			universe.onHover = () -> wake();
			Download.detect();
			if (!CompilerClient.supported()) byId("core-state").textContent = "needs a newer browser (WebAssembly exceptions)";
			route();
		});
		byId("back").onclick = back;
		byId("core").onclick = () -> {
			sky.kick(0.6);
			wake();
		};
		byId("sheet-ok").onclick = () -> byId("sheet").hidden = true;
		byId("sheet").onclick = (ev:js.html.Event) -> if (ev.target == byId("sheet")) byId("sheet").hidden = true;
		window.addEventListener("keydown", (ev:js.html.KeyboardEvent) -> {
			if (ev.key != "Escape" || world == null) return;
			if (world.escape()) return;
			if (world.current != null && document.activeElement.tagName != "CANVAS" && document.activeElement.closest(".cm-editor") == null) back();
		});
		window.addEventListener("popstate", route);
		// (the compiler wakes on the first touch anywhere: by the time a world
		// is picked, it is mostly downloaded)
		window.addEventListener("pointerdown", wake, {once: true});
	}

	static function wake()
		client.wake().catchError(e -> toast(Std.string(e)));

	static function go(e:Example) {
		window.history.pushState({id: e.id}, "", '#/${e.id}');
		world.enter(e);
	}

	static function back() {
		var id = world.current?.id;
		if (window.location.hash != "") window.history.pushState(null, "", window.location.pathname + window.location.search);
		world.leave();
		if (id != null) haxe.Timer.delay(() -> universe.focus(id), 50);
	}

	static function route() {
		if (examples == null) return;
		var id = ~/^#\/?/.replace(window.location.hash, "");
		var e = Lambda.find(examples, x -> x.id == id);
		if (e != null) world.enter(e) else if (world.current != null) world.leave();
	}
}
