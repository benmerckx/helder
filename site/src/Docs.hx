import Layout.*;
import hxmc.view.*;
import hxmc.web.*;
import sys.FileSystem;

using StringTools;

typedef Doc = {src:String, page:String, group:String, title:String};

// The docs, generated from the repository at build time: the narrative docs
// (docs/*.md), the roadmap and the plans, each package's README and ui's
// guide, rendered with Markdown (links between them made links between the
// pages; any other file a link to GitHub), and the packages' API reference
// (Api: the compiler's types, the sources' comments)
class Docs implements Markup {
	static var docs:Array<Doc> = [];

	static function collect():Array<Doc> {
		var out:Array<Doc> = [];
		function add(src:String, page:String, group:String) {
			if (FileSystem.exists(src)) out.push({src: src, page: page, group: group, title: Markdown.title(Site.read(src), src)});
		}
		add("README.md", "docs/overview.html", "Guides");
		for (n in ["using", "development", "testing", "porting", "hxmc"])
			add('docs/$n.md', 'docs/$n.html', "Guides");
		add("ROADMAP.md", "docs/roadmap.html", "Guides");
		for (p in Pages.PACKAGES)
			add('packages/${p[0]}/README.md', 'docs/packages/${p[0]}.html', "Packages");
		add("packages/ui/GUIDE.md", "docs/packages/ui-guide.html", "Packages");
		add("docs/plans/README.md", "docs/plans/index.html", "Plans");
		var plans = FileSystem.readDirectory("docs/plans").filter(n -> n.endsWith(".md") && n != "README.md");
		plans.sort(Reflect.compare);
		for (n in plans)
			add('docs/plans/$n', 'docs/plans/${n.substr(0, n.length - 3)}.html', "Plans");
		return out;
	}

	public static function all(api:Api) {
		docs = collect();
		Site.renderPage("docs/index.html", () -> Static.document(<Index/>));
		for (d in docs) {
			Site.renderPage(d.page, () -> {
				var md = new Markdown(href -> resolve(href, d.src));
				var html = md.render(Site.read(d.src));
				return Static.document(<DocPage doc={d} html={html} headings={md.headings}/>);
			});
		}
		for (p in Pages.PACKAGES)
			Site.renderPage('docs/api/${p[0]}.html', () -> Static.document(<ApiPage pkg={p[0]} name={p[1]} api={api}/>));
	}

	// a link of a Markdown file: to its page when it is one of the docs, else to GitHub
	static function resolve(href:String, src:String):String {
		if (~/^[a-z]+:/.match(href) || href.startsWith("#")) return href;
		var hash = "";
		var h = href.indexOf("#");
		if (h >= 0) {
			hash = href.substr(h);
			href = href.substr(0, h);
		}
		var path = normalize(haxe.io.Path.directory(src) + "/" + href);
		if (path.endsWith("/")) path = path.substr(0, path.length - 1);
		if (FileSystem.exists(path) && FileSystem.isDirectory(path) && FileSystem.exists(path + "/README.md")) {
			var d = Lambda.find(docs, d -> d.src == path + "/README.md");
			if (d != null) return Site.link(d.page) + hash;
		}
		var d = Lambda.find(docs, d -> d.src == path);
		if (d != null) return Site.link(d.page) + hash;
		return Site.github(path) + hash;
	}

	static function normalize(path:String):String {
		var out = [];
		for (part in path.split("/")) {
			if (part == "." || part == "") continue;
			if (part == ".." && out.length > 0 && out[out.length - 1] != "..") out.pop();
			else out.push(part);
		}
		return out.join("/");
	}

	static final GROUPS = ["Guides", "Packages", "API", "Plans"];

	// the docs' list, beside each page (below it on a phone)
	static function Sidebar(props:{current:String}):View {
		return <aside class="docs-nav" aria-label="Docs">
			{[
					for (g in GROUPS) {
						var items = g == "API" ? [for (p in Pages.PACKAGES) {page: 'docs/api/${p[0]}.html', title: p[1]}] : [
							for (d in docs) if (d.group == g) {page: d.page, title: d.title}
						];
						<div class="group">
							<h2>{g == "API" ? "API reference" : g}</h2>
							<ul>{[
								for (i in items)
									<li><a href={Site.link(i.page)} aria-current={i.page == props.current ? "page" : null}>{i.title}</a></li>
							]}</ul>
						</div>;
					}
			]}
		</aside>;
	}

	static function DocPage(props:{doc:Doc, html:String, headings:Array<Markdown.Heading>}):View {
		var toc = props.headings.filter(h -> h.level == 2);
		return <Page title={props.doc.title} section="Docs" description={props.doc.title + ": hxmc's documentation, generated from " + props.doc.src + "."}>
			<div class="wrap docs">
				<Sidebar current={props.doc.page}/>
				<article class="doc">
					<Raw cls="prose" html={props.html}/>
					<p class="note source">Generated from <a href={Site.github(props.doc.src)}>{props.doc.src}</a>.</p>
				</article>
				{toc.length < 2 ? null : <nav class="toc" aria-label="On this page">
					<h2>On this page</h2>
					<ul>{[for (h in toc) <li><a href={"#" + h.id}>{h.text}</a></li>]}</ul>
				</nav>}
			</div>
		</Page>;
	}

	// the first paragraph of a doc, as text
	static function summary(src:String):String {
		for (block in ~/\n\s*\n/g.split(Site.read(src))) {
			var t = block.trim();
			if (t == "" || t.startsWith("#") || t.startsWith("|") || t.startsWith("```") || t.startsWith("-") || t.startsWith(">")) continue;
			var s = Markdown.plain(t.replace("\n", " "));
			return s.length > 180 ? s.substr(0, s.lastIndexOf(" ", 177)) + "…" : s;
		}
		return "";
	}

	static function Index(props:{}):View {
		return <Page title="Docs" section="Docs" description="hxmc's documentation: guides, the packages' READMEs and API reference, the roadmap and design plans, generated from the repository.">
			<div class="wrap docs">
				<Sidebar current="docs/index.html"/>
				<article class="doc">
					<h1>Docs</h1>
					<p class="lead">Generated from the repository at each build: the guides in <code>docs/</code>, each package's README, an API reference read from the packages' types by the compiler, the roadmap and the design plans.</p>
					{[
						for (g in GROUPS)
							<section class="doc-group">
								<h2>{g == "API" ? "API reference" : g}</h2>
								<ul class="doc-list">{
									g == "API" ? [
										for (p in Pages.PACKAGES)
											<li><a href={Site.link('docs/api/${p[0]}.html')}>{p[1]}</a><span>{p[2]}</span></li>
									] : [
										for (d in docs) if (d.group == g) <li><a href={Site.link(d.page)}>{d.title}</a><span>{summary(d.src)}</span></li>
									]
								}</ul>
							</section>
					]}
				</article>
			</div>
		</Page>;
	}

	static function ApiPage(props:{pkg:String, name:String, api:Api}):View {
		var types = props.api.of(props.pkg);
		return <Page title={props.name + " API"} section="Docs" description={"The API of " + props.name + ", read from its typed modules by the compiler."}>
			<div class="wrap docs">
				<Sidebar current={'docs/api/${props.pkg}.html'}/>
				<article class="doc api">
					<h1>{props.name} <span class="muted">API</span></h1>
					<p>The public types of <code>{"hxmc." + props.pkg}</code>{Api.INCLUDE.get(props.pkg).length > 1 ? " and its packages " + Api.INCLUDE.get(props.pkg).slice(1).join(", ") : ""}, as the compiler types them, with the comments of their sources. The guide: <a href={Site.link('docs/packages/${props.pkg}.html')}>the README</a>.</p>
					{types.length == 0 ? <p class="note">(Read by the site build, with the compiler.)</p> : <Raw html={apiHtml(types)}/>}
				</article>
			</div>
		</Page>;
	}

	static function apiHtml(types:Array<Api.ApiType>):String {
		var b = new StringBuf();
		b.add('<nav class="api-index" aria-label="Types"><ul>');
		for (t in types)
			b.add('<li><a href="#${t.anchor}"><span class="kind kind-${t.kind}">${t.kind.charAt(0)}</span>${Esc.html(t.anchor)}</a></li>');
		b.add("</ul></nav>");
		var groups = [
			"new" => "Constructor", "static" => "Static", "instance" => "Instance", "case" => "Values", "field" => "Fields"
		];
		for (t in types) {
			b.add('<section class="api-type" id="${t.anchor}">');
			b.add('<h2><code>${t.sig}</code></h2>');
			b.add('<p class="where"><code>${Esc.html(t.path)}</code> · <a href="${Site.github(t.file)}#L${t.line}">${Esc.html(haxe.io.Path.withoutDirectory(t.file))}</a></p>');
			if (t.doc != "") b.add('<div class="api-doc">${t.doc}</div>');
			for (g in ["new", "case", "field", "static", "instance"]) {
				var fs = t.fields.filter(f -> f.group == g);
				if (fs.length == 0) continue;
				b.add('<h3>${groups.get(g)}</h3><dl>');
				for (f in fs) {
					b.add('<dt id="${t.anchor}.${Esc.html(f.name)}"><code>${f.sig}</code></dt>');
					b.add('<dd>${f.doc}</dd>');
				}
				b.add("</dl>");
			}
			b.add("</section>");
		}
		return b.toString();
	}
}
