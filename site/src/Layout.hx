import hxmc.view.*;
import hxmc.web.*;

// The shared layout: the head (the stylesheet, the island loader, the theme
// applied before the first paint), the header with the site's sections,
// and the footer; and the small components the pages share
class Layout implements Markup {
	public static final SECTIONS = [
		["compiler.html", "Compiler"],
		["hxmc.html", "hxmc"],
		["packages.html", "Packages"],
		["examples.html", "Examples"],
		["playground.html", "Playground"],
		["docs/index.html", "Docs"],
		["story.html", "Story"],
	];

	// (GitHub's mark, the header's link to the source)
	static final GH = "M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z";
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
						<a class="brand" href={Site.link("index.html")} aria-label="hxmc, home">hxmc</a>
						<SiteIslands.Menu links={links}/>
						<a class="gh" href={Site.REPO} aria-label="Source on GitHub" title="Source on GitHub"><svg width="18" height="18" viewBox="0 0 16 16" aria-hidden="true"><path d={GH}/></svg></a>
						<SiteIslands.Theme/>
					</div>
				</header>
				<main id="main">{props.children}</main>
				<footer class="foot">
					<div class="wrap">
						<p><a class="brand" href={Site.link("index.html")}>hxmc</a> The <a href="https://haxe.org">Haxe</a> compiler in Haxe, and a machine-code target.</p>
						<nav aria-label="More">
							<a href={Site.link("docs/index.html")}>Docs</a>
							<a href={Site.link("story.html")}>Story</a>
							<a href={Site.link("compiler.html#download")}>Download</a>
							<a href={Site.REPO}>GitHub</a>
						</nav>
						<p class="legal">Compiler GPL-2.0-or-later, as Haxe; runtime, std and packages MIT. Built {Date.now().toString().substr(0, 10)}{Site.version == null ? "" : " from " + Site.version}.</p>
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
