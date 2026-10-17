import hxmc.view.*;
import hxmc.web.*;

// The shared layout: the head (the stylesheet, the island loader, the theme
// applied before the first paint), the header with the site's sections,
// and the footer; and the small components the pages share
class Layout implements Markup {
	public static final SECTIONS = [
		["index.html", "Home"],
		["compiler.html", "Compiler"],
		["hxmc.html", "hxmc"],
		["packages.html", "Packages"],
		["examples.html", "Examples"],
		["playground.html", "Playground"],
		["docs/index.html", "Docs"],
		["story.html", "Story"],
	];

	// (the saved theme, before the page is painted: no flash of the other one)
	static final THEME_SCRIPT = "try{var t=localStorage.getItem('theme');if(t)document.documentElement.dataset.theme=t}catch(e){}";

	public static function Page(props:{
		title:String,
		description:String,
		section:String,
		?children:Any,
		?head:Any,
		?bodyClass:String
	}):View {
		var links:Array<SiteIslands.NavLink> = [
			for (s in SECTIONS) {href: Site.link(s[0]), label: s[1], current: s[1] == props.section}
		];
		var title = props.section == "Home" ? props.title : props.title + " · hxmc";
		return <html lang="en">
			<head>
				<meta charset="utf-8"/>
				<meta name="viewport" content="width=device-width, initial-scale=1"/>
				<title>{title}</title>
				<meta name="description" content={props.description}/>
				<meta name="color-scheme" content="light dark"/>
				<link rel="icon" href={Site.link("favicon.svg")} type="image/svg+xml"/>
				<link rel="stylesheet" href={Site.asset("style.css")}/>
				<script>{THEME_SCRIPT}</script>
				<script src={Site.asset("loader.js")} defer></script>
				{props.head}
			</head>
			<body class={props.bodyClass}>
				<a class="skip" href="#main">Skip to content</a>
				<header class="top">
					<div class="wrap bar">
						<a class="brand" href={Site.link("index.html")}><span class="logo" aria-hidden="true"></span>hxmc</a>
						<SiteIslands.Menu links={links}/>
						<SiteIslands.Theme/>
					</div>
				</header>
				<main id="main">{props.children}</main>
				<footer class="foot">
					<div class="wrap">
						<p>hxmc: <a href="https://haxe.org">Haxe</a>'s compiler ported to Haxe, and a target that writes machine code and WebAssembly.{" "}
						<a href={Site.REPO}>Source</a> · <a href={Site.link("docs/index.html")}>Docs</a> · <a href={Site.link("story.html")}>Story</a></p>
						<p class="muted">Built {Date.now().toString().substr(0, 10)}{Site.version == null ? "" : " from commit " + Site.version}.
						The compiler is GPL-2.0-or-later, as Haxe's; the runtime, std and packages are MIT.</p>
					</div>
				</footer>
			</body>
		</html>;
	}

	// raw HTML (Markdown, highlighted code), in an element
	public static function Raw(props:{html:String, ?cls:String, ?tag:String}):View {
		return props.tag == "section" ? <section class={props.cls} innerHTML={props.html}></section> : <div class={props.cls} innerHTML={props.html}></div>;
	}

	// code, highlighted
	public static function Code(props:{code:String, ?lang:String}):View
		return <Raw cls="codebox" html={Highlight.block(props.code, props.lang == null ? "haxe" : props.lang)}/>;

	// a page's heading block
	public static function Hero(props:{title:String, ?kicker:String, ?children:Any}):View {
		return <header class="hero">
			<div class="wrap">
				{props.kicker == null ? null : <p class="kicker">{props.kicker}</p>}
				<h1>{props.title}</h1>
				{props.children}
			</div>
		</header>;
	}

	// a JavaScript island hydrated by a hand-written function (the
	// playground's and the tables' scripts: globalThis.hxmcIslands[name]),
	// around markup the page renders
	public static function ScriptIsland(props:{name:String, script:String, ?load:Island.Load, ?children:Any}):View {
		var load:String = props.load == null ? Island.Load.Visible : props.load;
		return <hxmc-island data-island={props.name} data-load={load} data-src={Site.asset(props.script)}>{props.children}</hxmc-island>;
	}
}
