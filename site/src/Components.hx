using StringTools;

// hxmc.ui's widgets as a page of the docs (Docs: one of the packages'
// pages, beside ui's README and guide): WidgetDocs's reference, read from
// Widgets.hx and the widgets' examples at build time. An index of the
// widgets by category, then a section per widget: its doc, whether it is
// drawn or native, its variants, sizes and roles, its props with their
// defaults, its keys, its slots and states for a theme, the widgets that
// are its parts, and its example's source
class Components {
	public static final PAGE = "docs/packages/ui-components.html";
	public static final SOURCE = "packages/ui/src/hxmc/ui/widgets/Widgets.hx";
	public static final TITLE = "UI components";
	public static final SUMMARY = "Every widget of hxmc.ui: its props, keys, slots and states, its parts and an example, read from the sources at each build.";
	static final EXAMPLES = "packages/ui/examples/widgets";

	// the categories, in their order (a widget in none: Other)
	static final CATEGORIES:Array<{name:String, widgets:Array<String>}> = [
		{name: "Actions", widgets: ["Button", "Toggle", "ToggleGroup", "ButtonGroup", "Toolbar"]},
		{
			name: "Forms",
			widgets: [
				"Field", "Label", "Input", "Textarea", "NumberField", "TagInput", "InputGroup", "InputOTP", "Checkbox", "Switch", "RadioGroup", "Slider",
				"RangeSlider", "Select", "NativeSelect", "Combobox", "Listbox", "ColorPicker", "Calendar", "DatePicker"
			]
		},
		{
			name: "Overlays",
			widgets: [
				"Dialog", "AlertDialog", "Sheet", "Drawer", "PopoverButton", "HoverCard", "Tooltip", "DropdownMenu", "ContextMenu", "Menubar", "Command",
				"Toaster"
			]
		},
		{name: "Navigation", widgets: ["Tabs", "Breadcrumb", "Pagination", "NavigationMenu", "SidebarProvider", "Carousel"]},
		{
			name: "Data display",
			widgets: ["Table", "Tree", "Sortable", "Card", "Item", "Empty", "Alert", "Badge", "Avatar", "Kbd", "Progress", "Skeleton", "Spinner"]
		},
		{name: "Layout", widgets: ["Separator", "Split", "Collapsible", "Accordion", "AspectRatio", "ScrollArea"]},
		{name: "Charts", widgets: ["BarChart", "LineChart", "AreaChart", "PieChart"]}
	];

	// the page's body and its headings (the categories: "On this page")
	public static function render():{html:String, headings:Array<Markdown.Heading>} {
		var widgets:Array<Dynamic> = WidgetDocs.read(Site.read(SOURCE), EXAMPLES);
		var tops = widgets.filter(w -> w.part == null);
		var known = [for (c in CATEGORIES) for (n in c.widgets) n];
		var groups = CATEGORIES.concat([{name: "Other", widgets: [for (w in tops) if (known.indexOf(w.name) < 0) w.name]}]);
		var byName = [for (w in tops) (w.name : String) => w];
		var b = new StringBuf(), headings:Array<Markdown.Heading> = [];
		b.add('<h1>$TITLE</h1>');
		b.add('<p class="lead">${tops.length} widgets of <code>hxmc.ui</code> (${widgets.length} with their parts), unstyled: their look is a theme\'s rules for their slots, states, variants and sizes (<code>Shadcn.sheet</code> in the examples). Read from <a href="${Site.github(SOURCE)}">Widgets.hx</a> and <a href="${Site.github(EXAMPLES)}">the examples</a> at each build.</p>');
		b.add('<nav class="widget-index" aria-label="Widgets">');
		for (g in groups) {
			var names = g.widgets.filter(n -> byName.exists(n));
			if (names.length == 0) continue;
			b.add('<div><h2>${Esc.html(g.name)}</h2><ul>');
			for (n in names)
				b.add('<li><a href="#$n">$n</a></li>');
			b.add('</ul></div>');
		}
		b.add('</nav>');
		for (g in groups) {
			var names = g.widgets.filter(n -> byName.exists(n));
			if (names.length == 0) continue;
			var id = "category-" + g.name.toLowerCase().replace(" ", "-");
			headings.push({level: 2, text: g.name, id: id});
			b.add('<h2 class="widget-category" id="$id">${Esc.html(g.name)}</h2>');
			for (n in names) {
				var w = byName[n];
				b.add('<section class="api-type widget" id="$n">');
				widget(b, w, 3);
				for (p in widgets)
					if (p.part == w.name) {
						b.add('<div class="widget-part" id="${p.name}">');
						widget(b, p, 4);
						b.add('</div>');
					}
				if (w.example != null) {
					b.add('<details class="example"><summary>Example</summary>');
					b.add(Highlight.block((w.example : String).trim(), "haxe"));
					b.add('</details>');
				}
				b.add('</section>');
			}
		}
		return {html: b.toString(), headings: headings};
	}

	static function widget(b:StringBuf, w:Dynamic, level:Int) {
		b.add('<h$level><code>${w.name}</code></h$level>');
		var facts = [w.host == null || w.host == "drawn" ? "drawn" : 'native: ${Esc.html(w.host)}'];
		var variants:Array<String> = w.variants, sizes:Array<String> = w.sizes, roles:Array<String> = w.roles;
		if (variants != null && variants.length > 0) facts.push('variants ${codes(variants)}');
		if (sizes != null && sizes.length > 0) facts.push('sizes ${codes(sizes)}');
		if (roles != null && roles.length > 0) facts.push('roles ${codes(roles)}');
		if (w.popup == true) facts.push("its parts shown when opened");
		b.add('<p class="where">${facts.join(" · ")}</p>');
		if (w.doc != null && w.doc != "") b.add('<p>${text(sentence(w.doc))}</p>');
		var props:Array<Dynamic> = w.props;
		if (props != null && props.length > 0) {
			b.add('<div class="widget-scroll"><table class="widget-table"><thead><tr><th>Prop</th><th>Type</th><th></th></tr></thead><tbody>');
			for (p in props) {
				var dflt = p.def == null ? "" : ' <span class="muted">Default <code>${Esc.html(p.def)}</code>.</span>';
				b.add('<tr><td><code>${Esc.html(p.name)}${p.optional == true ? "?" : ""}</code></td><td><code>${Esc.html(p.type)}</code></td><td>${p.doc == null ? "" : text(sentence(p.doc))}$dflt</td></tr>');
			}
			b.add('</tbody></table></div>');
		}
		var keys:Array<Dynamic> = w.keys;
		if (keys != null && keys.length > 0) {
			b.add('<div class="widget-scroll"><table class="widget-table"><thead><tr><th>Keys</th><th></th></tr></thead><tbody>');
			for (k in keys)
				b.add('<tr><td>${[for (part in (k.keys : String).split(", ")) '<kbd>${Esc.html(part)}</kbd>'].join(" ")}</td><td>${text(sentence(k.does))}</td></tr>');
			b.add('</tbody></table></div>');
		}
		var slots:Array<String> = w.slots, states:Array<String> = w.states;
		var theme = [];
		if (slots != null && slots.length > 0) theme.push('slots ${codes(slots)}');
		if (states != null && states.length > 0) theme.push('states ${codes(states)}');
		if (theme.length > 0) b.add('<p class="where">For a theme: ${theme.join("; ")}</p>');
	}

	// (a comment as a sentence: its first letter capital, a full stop after it)
	static function sentence(s:String):String {
		s = s.trim();
		if (s == "") return s;
		s = s.charAt(0).toUpperCase() + s.substr(1);
		return s.endsWith(".") || s.endsWith(")") && s.endsWith(".)") ? s : s + ".";
	}

	// (a comment's text: escaped, its quoted names as code)
	static function text(s:String):String
		return ~/"([^"]+)"/g.map(Esc.html(s).replace("&quot;", '"'), r -> '<code>${r.matched(1)}</code>');

	static function codes(names:Array<String>):String
		return [for (n in names) '<code>${Esc.html(n)}</code>'].join(", ");
}
