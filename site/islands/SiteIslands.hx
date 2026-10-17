import hxmc.view.*;
import hxmc.view.Reactive.*;
import hxmc.web.*;

typedef NavLink = {href:String, label:String, current:Bool};

// The islands every page has, in code both the pages' build (the static
// renderer) and their bundle (site.js: site/client/SiteBundle.hx, the DOM
// renderer, by the port's JavaScript target) compile: the navigation (a
// menu button on a phone), the theme switch, and the tabs of an example's
// source files.
class SiteIslands implements Markup {
	// the site's sections; on a narrow screen behind a menu button
	static function MenuView(props:{links:Array<NavLink>}):View {
		var open = signal(false);
		return <nav class={() -> open.value ? "nav open" : "nav"} aria-label="Site">
			<button class="menu" type="button" aria-controls="nav-links" aria-expanded={() -> open.value ? "true" : "false"}
				onClick={() -> open.value = !open.value}>
				<span class="bars" aria-hidden="true"></span><span class="label">Menu</span>
			</button>
			<ul id="nav-links">{[
				for (l in props.links)
					<li><a href={l.href} aria-current={l.current ? "page" : null}>{l.label}</a></li>
			]}</ul>
		</nav>;
	}

	public static final Menu = Island.define("menu", MenuView, {script: "site.js", load: Idle});

	// light or dark, else the system's (an inline script in the page's head
	// applies the choice before the first paint: Layout)
	static function ThemeView(props:{}):View {
		return <button class="theme" type="button" aria-label="Switch between light and dark" title="Light or dark" onClick={() -> toggle()}>
			<svg class="moon" width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>
			<svg class="sun" width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4.5"/><path d="M12 1.5v3M12 19.5v3M1.5 12h3M19.5 12h3M4.6 4.6l2.1 2.1M17.3 17.3l2.1 2.1M4.6 19.4l2.1-2.1M17.3 6.7l2.1-2.1"/></svg>
		</button>;
	}

	static function toggle() {
		#if js
		var root = js.Browser.document.documentElement;
		var current = root.dataset.theme;
		if (current == null || current == "")
			current = js.Browser.window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
		var next = current == "dark" ? "light" : "dark";
		root.dataset.theme = next;
		try js.Browser.window.localStorage.setItem("theme", next) catch (_:Dynamic) {}
		#end
	}

	public static final Theme = Island.define("theme", ThemeView, {script: "site.js", load: Idle});

	// an example's files: one shown at a time (the panels id-0, id-1, ...;
	// the first shown in the page, the others hidden)
	static function TabsView(props:{id:String, labels:Array<String>}):View {
		var current = signal(0);
		#if js
		effect(() -> {
			var c = current.value;
			for (k in 0...props.labels.length) {
				var panel = js.Browser.document.getElementById(props.id + "-" + k);
				if (panel != null) panel.hidden = k != c;
			}
		});
		#end
		return <div class="tabs" role="tablist">{[
			for (k in 0...props.labels.length)
				<button type="button" role="tab" aria-controls={props.id + "-" + k} aria-selected={() -> current.value == k ? "true" : "false"}
					onClick={() -> current.value = k}>{props.labels[k]}</button>
		]}</div>;
	}

	public static final Tabs = Island.define("tabs", TabsView, {script: "site.js", load: Visible});
}
