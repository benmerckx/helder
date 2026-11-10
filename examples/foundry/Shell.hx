import Model;
import helder.ui.*;
import helder.ui.widgets.Controls.Segmented;
import helder.ui.widgets.Controls.Slider;
import helder.ui.widgets.Controls.Tip;
import helder.ui.widgets.Theme;
import helder.ui.widgets.Theme.c;
import helder.ui.widgets.WindowButtons.WindowControls;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The window: the glyphs (the first letters to draw, then every group) on
// the left; the board with its tools in the middle, the draft font under
// it; the font's settings on the right (its name and export, the pen,
// the proportions, this glyph's spacing, agents); a status bar.
class Shell implements Markup {
	public static inline var SIDEBAR = 272;
	public static inline var INSPECTOR = 264;

	public static final PRESETS:Array<{name:String, pen:Pen}> = [
		{name: "Marker", pen: {width: 84, contrast: 0, angle: 30, cap: Round}},
		{name: "Fine", pen: {width: 40, contrast: 0, angle: 30, cap: Round}},
		{name: "Brush", pen: {width: 110, contrast: 0.55, angle: 20, cap: Round}},
		{name: "Nib", pen: {width: 120, contrast: 0.85, angle: 35, cap: Flat}}
	];

	static function t(name:String):Color
		return Color.parse('var(--$name)');

	// the theme's parts and Foundry's own (a glyph's cell, a first letter's chip)
	public static final sheet:StyleSheet = {
		rules: Theme.sheet.rules.concat([
			{slot: "cell", style: {height: 56, radius: Theme.RADIUS_M, background: t("well"), borderWidth: 1, borderColor: Color.TRANSPARENT, cursor: Pointer,
				alignItems: Center, padding: [4, 2, 3, 2], overflow: Hidden}},
			{slot: "cell", when: ["hover"], style: {background: t("hover")}},
			{slot: "cell", when: ["data-on=true"], style: {background: t("on"), borderColor: t("accent")}},
			{slot: "cell", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 1, outlineColor: t("focus")}},
			{slot: "chip", style: {width: 28, height: 34, radius: Theme.RADIUS, background: t("bg"), borderWidth: 1, borderColor: Color.TRANSPARENT,
				cursor: Pointer, alignItems: Center, justify: Center}},
			{slot: "chip", when: ["hover"], style: {background: t("hover")}},
			{slot: "chip", when: ["data-on=true"], style: {borderColor: t("accent")}},
			{slot: "chip", when: ["data-done=true"], style: {background: t("on")}},
			{slot: "starter", style: {padding: 8, radius: Theme.RADIUS_M + 2, background: t("bg"), borderWidth: 1, borderColor: t("line"), cursor: Pointer}},
			{slot: "starter", when: ["hover"], style: {background: t("hover"), borderColor: t("edge")}},
			{slot: "starter", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 1, outlineColor: t("focus")}},
		]),
		light: Theme.light,
		dark: Theme.dark
	};

	public static function view(ws:Workshop):View
		return <view slot="body" grow={1} direction="row" min-height={0}>
			{sidebar(ws)}
			<view tag="main" grow={1} min-width={0} direction="column" background={c("bg")}>
				{header(ws)}
				{board(ws)}
				{preview(ws)}
				{status(ws)}
			</view>
			{inspector(ws)}
			{Start.view(ws)}
		</view>;

	static function icon(src:Svg, size = Theme.ICON_S):View
		return <image src={src} width={size} height={size} shrink={0}/>;

	// ---- the glyphs

	static function sidebar(ws:Workshop):View
		return <view tag="sidebar" slot="panel" width={SIDEBAR} shrink={0} border-width="0 1 0 0">
			<view direction="row" align-items="center" column-gap={8} drag-region height={Theme.HEADER} padding={'0 ${Theme.PAD}'} shrink={0}
				border-width="0 0 1 0" border-color={c("line")}>
				<Show when={SafeArea.titlebar() != null}><view direction="row" align-items="center" padding="0 6 0 0"><WindowControls/></view></Show>
				<view width={20} height={20} radius={5} background={c("accent")} align-items="center" justify="center">
					<text color={c("accent-fg")} font-family={Draft.FAMILY} font-size={14} line-height="14px">a</text>
				</view>
				<text font-weight={Theme.MEDIUM}>Foundry</text>
				<view grow={1}/>
				<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg3")} font-variant-numeric="tabular-nums">{() -> {
					var p = ws.progress();
					'${p.drawn + p.borrowed} / ${p.total}';
				}}</text>
			</view>
			<scroll tag="glyphs" grow={1} min-height={0} padding="8 10 12" row-gap={14}>
				{start(ws)}
				<For each={Charset.groups}>{(group:Read<{name:String, chars:Array<String>}>) -> {
					var g = group();
					<view row-gap={6}>
						<view slot="section-head" padding="0 2">
							<text font-size={Theme.SMALL} grow={1}>{g.name}</text>
							<text font-size={Theme.SMALL} color={c("fg3")} font-family={Theme.CODE}>{() -> {
								var f = ws.face(), n = 0;
								for (ch in g.chars)
									if (Workshop.state(f, ch) != "empty") n++;
								'$n/${g.chars.length}';
							}}</text>
						</view>
						<view display="grid" grid-template-columns="repeat(5, 1fr)" column-gap={4} row-gap={4} role="list" label={g.name}>
							<For each={g.chars}>{(ch:Read<String>) -> cell(ws, ch())}</For>
						</view>
					</view>;
				}}</For>
			</scroll>
		</view>;

	static function cell(ws:Workshop, char:String):View {
		var state = memo(() -> Workshop.state(ws.face(), char));
		return <view:button tag={"glyph-" + Charset.code(char)} slot="cell" role="listitem" label={'$char, ${state()}'} focusable
			data-on={ws.current() == char ? "true" : "false"} onPress={() -> ws.open(char)}>
			<view grow={1} align-self="stretch" align-items="center" justify="center">
				<Show when={state() != "empty"} fallback={<text font-size={20} color={c("fg3")} opacity={0.45}>{char}</text>}>
					{thumb(ws, char)}
				</Show>
			</view>
			<Show when={ws.agentGlyphs().indexOf(char) >= 0}>
				<image position="absolute" top={4} right={4} src={Icons.sparkles} width={10} height={10} color={c("violet")} label="Drawn by an agent"/>
			</Show>
			<view direction="row" align-items="center" column-gap={3} height={12}>
				<text font-size={10} line-height="12px" color={c("fg3")}>{char}</text>
				<Show when={state() == "borrowed"}><view width={4} height={4} radius={2} background={c("accent-ink")} label="Borrowed"/></Show>
			</view>
		</view:button>;
	}

	static function thumb(ws:Workshop, char:String):Node {
		var t = new Thumb(ws, char);
		t.style.alignSelf = Stretch;
		t.style.grow = 1;
		renderEffect(() -> {
			ws.face();
			ws.dark();
		}, _ -> t.char = char);
		return t;
	}

	// the first letters, in order, while some are not drawn
	static function start(ws:Workshop):View {
		var next = memo(() -> {
			var f = ws.face();
			return Lambda.find(Charset.start, ch -> !Model.drawn(f, ch));
		});
		return <Show when={next() != null}>
			<view tag="start" row-gap={8} padding="10" radius={Theme.RADIUS_M} background={c("well")}>
				<view direction="row" align-items="center" column-gap={6}>
					{icon(Icons.sparkles, 12)}
					<text font-weight={Theme.MEDIUM} grow={1}>Start with these</text>
					<text font-size={Theme.SMALL} color={c("fg3")}>{() -> {
						var f = ws.face();
						'${Charset.start.filter(ch -> Model.drawn(f, ch)).length} of ${Charset.start.length}';
					}}</text>
				</view>
				<view direction="row" column-gap={3}>
					<For each={Charset.start}>{(ch:Read<String>) -> {
						var char = ch();
						<view:button tag={"start-" + char} slot="chip" role="button" label={"Draw " + char} focusable
							data-on={ws.current() == char ? "true" : "false"} data-done={Model.drawn(ws.face(), char) ? "true" : "false"}
							onPress={() -> ws.open(char)}>
							<text font-size={16} color={Model.drawn(ws.face(), char) ? c("accent-ink") : c("fg2")}>{char}</text>
						</view:button>;
					}}</For>
				</view>
				<text font-size={Theme.SMALL} color={c("fg2")} line-height="16px">{() -> {
					var n = next() ?? "";
					'$n · ${Charset.why.get(n) ?? ""}';
				}}</text>
			</view>
		</Show>;
	}

	// ---- the board

	static function header(ws:Workshop):View
		return <view tag="header" direction="row" align-items="center" column-gap={8} drag-region height={Theme.HEADER} shrink={0} padding={'0 ${Theme.PAD}'}
			border-width="0 0 1 0" border-color={c("line")}>
			<view direction="row" align-items="baseline" column-gap={8} min-width={0} shrink={1}>
				<text font-size={15} font-weight={Theme.MEDIUM}>{ws.current}</text>
				<text color={c("fg3")} font-family={Theme.CODE} font-size={Theme.SMALL}>{() -> unicode(ws.current())}</text>
				<text color={c("fg3")} font-size={Theme.SMALL} max-lines={1}>{() -> describe(ws)}</text>
			</view>
			<view grow={1}/>
			<Segmented tag="tool" label="Tool" value={ws.tool} onChange={v -> ws.tool(v)} options={[
				{value: "draw", label: "Draw", icon: Icons.pen, hint: "Draw (P)"},
				{value: "adjust", label: "Adjust", icon: Icons.pointer, hint: "Adjust (V)"},
				{value: "erase", label: "Erase", icon: Icons.eraser, hint: "Erase (E)"}
			]}/>
			<view width={1} height={16} background={c("line")}/>
			<Tip label={ws.guide() ? "Hide the tracing letter" : "Show the tracing letter"} keys="T">
				<view:button tag="guide" slot="button" role="button" label="Tracing letter" focusable data-on={ws.guide() ? "true" : "false"}
					onPress={() -> ws.guide(!ws.guide.peek())}>{icon(Icons.eye)}</view:button>
			</Tip>
		</view>;

	static function describe(ws:Workshop):String {
		var f = ws.face(), char = ws.current(), g = Model.glyph(f, char);
		var parts = Charset.parts(f, char), group = Lambda.find(Charset.groups, g -> g.chars.indexOf(char) >= 0)?.name ?? "";
		return switch Workshop.state(f, char) {
			case "drawn":
				var n = g == null ? 0 : g.lines.length;
				'$group · $n ${n == 1 ? "line" : "lines"}';
			case "borrowed": '$group · ${Charset.describe(parts)}';
			case _: '$group · not drawn yet';
		}
	}

	static function unicode(char:String):String
		return "U+" + StringTools.hex(Charset.code(char), 4);

	static function board(ws:Workshop):View {
		var area = signal({w: 0.0, h: 0.0});
		return <view tag="board-area" grow={1} min-height={0} position="relative" overflow="hidden" onResize={e -> area({w: e.target.width, h: e.target.height})}>
			{boardNode(ws)}
			{guides(ws, area)}
			<view position="absolute" top={14} left={0} right={0} align-items="center" pointer-events="none">
				<Show when={Workshop.state(ws.face(), ws.current()) == "borrowed" || Charset.parts(ws.face(), ws.current()).length > 0
					&& Model.drawn(ws.face(), ws.current())}>{borrowed(ws)}</Show>
			</view>
			<view position="absolute" bottom={16} left={0} right={0} align-items="center" pointer-events="none">
				<Show when={Workshop.state(ws.face(), ws.current()) == "empty"}>
					<view slot="floating" direction="row" align-items="center" column-gap={8} padding="7 12" shadow={Theme.popover()}>
						{icon(Icons.pen, 12)}
						<text color={c("fg2")}>{() -> 'Draw ${ws.current()}: press and drag, one line per stroke. Shift draws straight.'}</text>
					</view>
				</Show>
			</view>
			<view position="absolute" top={14} right={14} pointer-events="none">
				<Show when={ws.agent() != ""}>
					<view tag="agent" direction="row" align-items="center" column-gap={7} padding="6 12 6 10" radius={14} transition="fade slide-down"
						background={c("bg")} border-width={1} border-color={c("violet")} shadow={"0 0 18 " + (ws.dark() ? "rgba(185,174,224,0.35)" : "rgba(108,79,179,0.25)")}>
						<image src={Icons.sparkles} width={13} height={13} color={c("violet")}/>
						<text color={c("violet")} font-weight={Theme.MEDIUM}>{ws.agent}</text>
					</view>
				</Show>
			</view>
		</view>;
	}

	static function boardNode(ws:Workshop):Node {
		var b = new Board(ws);
		b.style.position = Absolute;
		b.style.inset = 0;
		renderEffect(() -> {
			ws.face();
			ws.current();
			ws.tool();
			ws.selected();
			ws.guide();
			ws.dark();
			ws.agentStroke();
			0;
		}, _ -> b.repaint());
		return b;
	}

	// the guides' names, beside them
	static function guides(ws:Workshop, area:Read<{w:Float, h:Float}>):View
		return <view position="absolute" left={0} top={0} bottom={0} width={110} pointer-events="none">
			<For each={() -> {
				var f = ws.face(), m = f.metrics, a = area(), v = Board.vertical(f, a.h, a.w);
				var close = Math.abs(m.ascender - m.capHeight) * v.scale < 16;
				[
					{name: close ? "Capitals, ascenders" : "Ascenders", y: v.base - m.ascender * v.scale - 16},
					{name: "Capitals", y: close ? -100 : v.base - m.capHeight * v.scale - 16},
					{name: "x-height", y: v.base - m.xHeight * v.scale - 16},
					{name: "Baseline", y: v.base - 16},
					{name: "Descenders", y: v.base - m.descender * v.scale + 4}
				];
			}} keyed={false}>{(g:Read<{name:String, y:Float}>) -> <text position="absolute" left={14} top={g().y} font-size={10} color={c("fg3")}
				opacity={g().y < 0 ? 0 : 1}>{g().name}</text>}</For>
		</view>;

	static function borrowed(ws:Workshop):View
		return <view tag="borrowed" slot="floating" direction="row" align-items="center" column-gap={6} padding="4 4 4 12" pointer-events="auto"
			shadow={Theme.popover()}>
			{icon(Icons.component, 12)}
			<text color={c("fg2")} padding="0 4 0 0">{() -> Charset.describe(Charset.parts(ws.face(), ws.current()))}</text>
			<view:button tag="adopt" slot="button" role="button" label="Make it its own" focusable onPress={() -> ws.adopt(ws.current())}>
				{icon(Icons.scissors, 12)}<text>Make it its own</text>
			</view:button>
			<Show when={!Model.drawn(ws.face(), ws.current())}>
				<view:button tag="own" slot="button" role="button" label="Draw it myself" focusable onPress={() -> ws.own(ws.current())}>
					{icon(Icons.pen, 12)}<text>Draw it myself</text>
				</view:button>
			</Show>
		</view>;

	// ---- the draft font

	static final SAMPLES = ["Hamburgefonstiv", "The quick brown fox jumps over the lazy dog", "Sphinx of black quartz, judge my vow!", "Über café, ¿sí? Ça va."];

	static function preview(ws:Workshop):View
		return <view tag="preview" shrink={0} border-width="1 0 0 0" border-color={c("line")} padding={'10 ${Theme.PAD} 12'} row-gap={8}>
			<view direction="row" align-items="center" column-gap={8}>
				<text slot="section-head" font-size={Theme.SMALL}>Preview</text>
				<text font-size={Theme.SMALL} color={c("fg3")} grow={1}>Type to try it, as an installed font draws it</text>
				<view direction="row" column-gap={2}>
					<For each={SAMPLES}>{(s:Read<String>) -> {
						var text = s();
						<view:button slot="button" role="button" label={text} focusable data-on={ws.sample() == text ? "true" : "false"} onPress={() -> ws.sample(text)}>
							<text font-size={Theme.SMALL}>{text.substr(0, 3)}</text>
						</view:button>;
					}}</For>
				</view>
				<Segmented tag="size" label="Size" value={() -> Std.string(Std.int(ws.size()))} onChange={v -> ws.size(Std.parseFloat(v))} options={[
					{value: "32", label: "S"},
					{value: "56", label: "M"},
					{value: "96", label: "L"}
				]}/>
			</view>
			<field tag="sample" slot="input" font-family={Draft.FAMILY} font-size={ws.size} label="Preview text" value={ws.sample} placeholder="Type here"
				onInput={e -> ws.sample(e.text)}/>
			<text font-family={Draft.FAMILY} font-size={15} line-height="22px" color={c("fg2")} max-lines={1} text-overflow="ellipsis">
				Brave little letters, jumping quickly over 1,234 dozen boxes. ÀÉÎÕÜ àéîõü ç ñ ¿? ¡!
			</text>
		</view>;

	static function status(ws:Workshop):View
		return <view tag="status" direction="row" align-items="center" column-gap={10} height={26} shrink={0} padding={'0 ${Theme.PAD}'}
			border-width="1 0 0 0" border-color={c("line")}>
			<text font-size={Theme.SMALL} color={c("fg3")} grow={1} max-lines={1} text-overflow="ellipsis">{() -> ws.status() == "" ? hint(ws) : ws.status()}</text>
			<text font-size={Theme.SMALL} color={c("fg3")}>{() -> {
				var p = ws.progress();
				'${p.drawn} drawn · ${p.borrowed} borrowed';
			}}</text>
			<view direction="row" align-items="center" column-gap={5}>
				<view width={6} height={6} radius={3} background={ws.mcp() == "" ? c("fg3") : c("green")}/>
				<text font-size={Theme.SMALL} color={c("fg3")}>{() -> ws.mcp() == "" ? "No agent link" : "Agents can connect"}</text>
			</view>
		</view>;

	static function hint(ws:Workshop):String
		return switch ws.tool() {
			case "adjust": "Drag a knot or a line. Double-click a knot for a corner. Delete removes. Arrows nudge.";
			case "erase": "Drag over lines to erase them.";
			case _: "Press and drag to draw a line. Ends near another line join it; knots near a guide rest on it.";
		}

	// ---- the font's settings

	static function inspector(ws:Workshop):View
		return <view tag="inspector" slot="panel" width={INSPECTOR} shrink={0} border-width="0 0 0 1">
			<view direction="row" align-items="center" column-gap={6} drag-region height={Theme.HEADER} padding={'0 ${Theme.PAD}'} shrink={0}
				border-width="0 0 1 0" border-color={c("line")}>
				<view grow={1}/>
				<Show when={Workshop.canInstall()}>
					<view:button tag="install" slot="button" role="button" label="Install the font" focusable onPress={ws.install}>
						<text>Install</text>
					</view:button>
				</Show>
				<view:button tag="export" slot="primary" role="button" label="Export the font" focusable onPress={ws.export}>
					{icon(Icons.download)}<text>Export .ttf</text>
				</view:button>
			</view>
			<scroll grow={1} min-height={0}>
				<view slot="section" border-width={0}>
					<view slot="section-head"><text>Font</text></view>
					<view slot="field">
						<text slot="field-label">Name</text>
						<field tag="name" slot="field-input" font-family={Theme.UI} label="Font name" value={() -> ws.face().name} onInput={e -> ws.rename(e.text)}/>
					</view>
				</view>
				{pen(ws)}
				{proportions(ws)}
				{spacing(ws)}
				{agents(ws)}
			</scroll>
		</view>;

	static function pen(ws:Workshop):View {
		var p = () -> ws.face().pen;
		function set(next:Pen)
			ws.setPen(next, "pen");
		return <view tag="pen" slot="section">
			<view slot="section-head"><text grow={1}>Pen</text><text color={c("fg3")} font-weight={400}>{() -> Draft.weightName(p())}</text></view>
			<Segmented tag="preset" label="Pen" value={() -> preset(p())} onChange={name -> {
				var found = Lambda.find(PRESETS, x -> x.name == name);
				if (found != null) ws.setPen(found.pen);
			}} options={[for (x in PRESETS) {value: x.name, label: x.name}]}/>
			<Slider tag="weight" label="Weight" value={() -> p().width} min={20} max={200} step={1} onChange={v -> set({width: v, contrast: p().contrast,
				angle: p().angle, cap: p().cap})}/>
			<Slider tag="contrast" label="Contrast" value={() -> p().contrast * 100} min={0} max={100} step={1} unit="%" onChange={v -> set({width: p().width,
				contrast: v / 100, angle: p().angle, cap: p().cap})}/>
			<Slider tag="angle" label="Angle" value={() -> p().angle} min={-90} max={90} step={1} unit="°" onChange={v -> set({width: p().width,
				contrast: p().contrast, angle: v, cap: p().cap})}/>
			<Segmented tag="ends" label="Ends" value={() -> (p().cap : String)} onChange={v -> ws.setPen({width: p().width, contrast: p().contrast,
				angle: p().angle, cap: v})} options={[{value: "round", label: "Round ends"}, {value: "flat", label: "Flat ends"}]}/>
		</view>;
	}

	static function preset(pen:Pen):String {
		for (x in PRESETS)
			if (x.pen.width == pen.width && x.pen.contrast == pen.contrast && x.pen.angle == pen.angle && x.pen.cap == pen.cap) return x.name;
		return "";
	}

	static function proportions(ws:Workshop):View {
		var m = () -> ws.face().metrics;
		function set(f:Metrics->Metrics)
			ws.setMetrics(f(m()), "metrics");
		return <view tag="proportions" slot="section">
			<view slot="section-head"><text>Proportions</text></view>
			<Slider tag="x-height" label="x-height" value={() -> m().xHeight} min={320} max={640} step={2} onChange={v -> set(x -> {xHeight: v,
				capHeight: x.capHeight, ascender: x.ascender, descender: x.descender, spacing: x.spacing})}/>
			<Slider tag="cap-height" label="Capitals" value={() -> m().capHeight} min={480} max={840} step={2} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: v, ascender: x.ascender, descender: x.descender, spacing: x.spacing})}/>
			<Slider tag="ascender" label="Ascenders" value={() -> m().ascender} min={560} max={900} step={2} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: x.capHeight, ascender: v, descender: x.descender, spacing: x.spacing})}/>
			<Slider tag="descender" label="Descenders" value={() -> -m().descender} min={120} max={380} step={2} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: x.capHeight, ascender: x.ascender, descender: -v, spacing: x.spacing})}/>
			<Slider tag="spacing" label="Spacing" value={() -> m().spacing} min={0} max={200} step={1} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: x.capHeight, ascender: x.ascender, descender: x.descender, spacing: v})}/>
		</view>;
	}

	static function spacing(ws:Workshop):View {
		var g = () -> {
			ws.face();
			return ws.glyph(ws.current());
		};
		return <view tag="glyph" slot="section">
			<view slot="section-head"><text grow={1}>{() -> 'Glyph ${ws.current()}'}</text></view>
			<view slot="fields" direction="row" column-gap={6}>
				<Slider tag="left" label="Left" value={() -> g().left ?? 0} min={-150} max={150} step={1} onChange={v -> ws.setSpacing(ws.current(), v,
					g().right ?? 0, "space")}/>
				<Slider tag="right" label="Right" value={() -> g().right ?? 0} min={-150} max={150} step={1} onChange={v -> ws.setSpacing(ws.current(),
					g().left ?? 0, v, "space")}/>
			</view>
			<view direction="row" column-gap={4}>
				<view:button tag="clear" slot="button" role="button" label="Clear this glyph" focusable onPress={() -> ws.clear(ws.current())}>
					{icon(Icons.trash, 12)}<text>Clear</text>
				</view:button>
			</view>
		</view>;
	}

	static function agents(ws:Workshop):View
		return <view tag="agents" slot="section">
			<view slot="section-head">{icon(Icons.sparkles, 12)}<text>Draw with an agent</text></view>
			<Show when={ws.mcp() != ""} fallback={<text color={c("fg3")} line-height="17px">Agents connect to the desktop app over MCP.</text>}>
				<text color={c("fg2")} line-height="17px">Add Foundry to any agent that speaks MCP, as an HTTP server, then ask it for letters. Its strokes are written out here, in violet, and undo like yours.</text>
				<view padding="6 8" radius={Theme.RADIUS} background={c("well")}>
					<text font-family={Theme.CODE} font-size={Theme.SMALL} color={c("fg2")} user-select="text" selectable>{ws.mcp}</text>
				</view>
			</Show>
		</view>;
}
