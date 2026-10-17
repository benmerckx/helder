import hxmc.theme.Shadcn;
import hxmc.theme.Tailwind;
import hxmc.theme.Tw;
import hxmc.ui.DimValue;

// packages/theme (make theme-check), on Eval: Tailwind's classes read as
// rules (Tailwind.rules, each as Tailwind.describe writes it), Tw's rules
// made at compile time, shadcn's sheet made; the classes Tw rejects at
// compile time (test/reject, "// expect:" lines; with the tool's path as
// the argument).
class ThemeTest {
	static var checks = 0;
	static var failed = 0;

	static function check(name:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('FAILED $name' + (detail == null ? "" : ": " + detail));
		}
	}

	// the rules of a class list, one line each
	static function rules(classes:String, ?variant:String, ?size:String):String
		return Tailwind.rules("x", classes, variant, size).map(Tailwind.describe).join("\n");

	static function same(classes:String, want:String, ?variant:String, ?size:String) {
		var got = rules(classes, variant, size);
		check(classes, got == want, 'got\n$got\nwant\n$want');
	}

	static function rejected(classes:String, want:String) {
		var message = try {
			Tailwind.rules("x", classes);
			"accepted";
		} catch (e:String) e;
		check('rejects $classes', message == want, message);
	}

	static function main() {
		layout();
		colours();
		text();
		variants();
		shorthands();
		more();
		motion();
		ignored();
		macro_();
		sheet();
		var tool = Sys.args()[0];
		if (tool != null) rejects(tool, "packages/theme/test/reject");
		Sys.println('ThemeTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function layout() {
		same("p-2", "x padding=8");
		same("px-4 py-2", "x padding=8 16 8 16");
		same("pl-8 -mx-1 my-1", "x padding=0 0 0 32 margin=4 -4 4 -4");
		same("size-4", "x width=16 height=16");
		same("h-9 w-full min-w-0 max-w-lg", "x height=36 width=100% minWidth=0 maxWidth=512");
		same("h-[1.15rem] w-1/2 h-px min-w-[8rem] w-fit h-auto", "x height=Auto width=FitContent minWidth=128");
		same("flex items-center justify-between gap-1.5", "x display=Flex direction=Row alignItems=Center justify=SpaceBetween gap=6");
		same("flex flex-col gap-x-3 gap-y-0.5", "x display=Flex direction=Column columnGap=12 rowGap=2");
		same("inline-flex shrink-0 flex-1 self-start", "x display=Flex direction=Row shrink=0 flex=1 alignSelf=Start");
		same("grid place-content-center", "x display=Grid alignContent=Center justify=Center");
		same("grid grid-cols-2 auto-rows-min grid-rows-[auto_auto]",
			"x display=Grid gridTemplateColumns=minmax(Px(0), Fr(1)) minmax(Px(0), Fr(1)) gridAutoRows=MinContent gridTemplateRows=Auto Auto");
		same("col-start-2 row-span-2 row-start-1 justify-self-end", "x gridColumn=2/0 span 1 gridRow=1/0 span 2 justifySelf=End");
		same("absolute inset-0 top-1/2 z-50", "x position=Absolute left=0 right=0 top=50% bottom=0 zIndex=50");
		same("overflow-hidden pointer-events-none opacity-50 cursor-not-allowed",
			"x overflow=Hidden pointerEvents=None opacity=0.5 cursor=NotAllowed");
		same("rounded-md", "x radius=8");
		same("rounded-sm rounded-xl rounded-[4px] rounded-full", "x radius=1000000");
		same("rounded-t-md rounded-b-[2px]", "x corners=8 8 2 2");
		same("border", "x borderWidth=1");
		same("border border-b-0", "x borders=1 1 0 1");
		same("border-x-2", "x borders=0 2 0 2");
		same("translate-x-[calc(100%-2px)]", "x transform=translateX(100%) translateX(-2px)");
		same("-translate-x-1/2 translate-y-[-50%] rotate-45", "x transform=translateX(-50%) translateY(-50%) rotate(45deg)");
		same("translate-x-0", "x transform=none");
	}

	static function colours() {
		same("bg-primary text-primary-foreground", "x background=var(--primary) color=var(--primary-foreground)");
		same("bg-primary/90 border-input ring-ring/50", "x background=var(--primary)/90 borderColor=var(--input) ringColor=var(--ring)/50");
		same("text-white bg-black/50 bg-transparent border-transparent", "x color=rgb(255, 255, 255) background=transparent borderColor=transparent");
		same("ring-[3px]", "x ringWidth=3");
		same("ring-2 ring-offset-2 ring-offset-background ring-inset", "x ringWidth=2 ringOffsetWidth=2 ringOffsetColor=var(--background) ringInset=true");
		same("shadow-xs", "x shadow=0 1 2 0 rgba(0, 0, 0, 0.05)");
		same("shadow-sm", "x shadow=0 1 3 0 rgba(0, 0, 0, 0.1), 0 1 2 -1 rgba(0, 0, 0, 0.1)");
		same("shadow-none", "x shadow=none");
	}

	static function text() {
		same("text-sm font-medium", "x fontSize=14 lineHeight=1.4286 fontWeight=500");
		// (leading-* beats text-*'s line height, whichever comes first)
		same("leading-none text-sm", "x lineHeight=1 fontSize=14");
		same("text-sm leading-none", "x fontSize=14 lineHeight=1");
		same("text-sm/6", "x fontSize=14 lineHeight=1.7143");
		same("text-xs tracking-widest", "x fontSize=12 lineHeight=1.3333 letterSpacing=1.2");
		same("text-[0.8rem] whitespace-nowrap truncate", "x fontSize=12.8 textWrap=NoWrap overflow=Hidden textOverflow=Ellipsis");
		same("underline uppercase text-center font-mono tabular-nums",
			"x textDecoration=1 textTransform=Uppercase textAlign=Center fontFamily=monospace fontVariantNumeric=tabular-nums");
		same("text-destructive!", "x color=var(--destructive)");
	}

	static function variants() {
		same("hover:bg-accent bg-primary", "x background=var(--primary)\nx hover: background=var(--accent)");
		// (Tailwind's order, not the list's: aria after focus-visible, dark after both)
		same("dark:aria-invalid:ring-destructive/40 aria-invalid:ring-destructive/20 focus-visible:ring-ring/50",
			"x focus-visible: ringColor=var(--ring)/50\nx aria-invalid=true: ringColor=var(--destructive)/20\n"
			+ "x dark aria-invalid=true: ringColor=var(--destructive)/40");
		same("data-[state=checked]:bg-primary data-[disabled]:opacity-50 data-[state=\"open\"]:bg-accent",
			"x data-state=checked: background=var(--primary)\nx data-disabled: opacity=0.5\nx data-state=open: background=var(--accent)");
		same("aria-selected:bg-accent data-placeholder:text-muted-foreground",
			"x aria-selected=true: background=var(--accent)\nx data-placeholder: color=var(--muted-foreground)");
		same("disabled:opacity-50 active:opacity-90 placeholder:text-muted-foreground",
			"x placeholder: color=var(--muted-foreground)\nx active: opacity=0.9\nx disabled: opacity=0.5");
		same("peer-disabled:opacity-50 group-data-[disabled=true]:opacity-50 has-data-[slot=card-action]:gap-2",
			"x group:data-disabled=true: opacity=0.5\nx peer:disabled: opacity=0.5\nx has:data-slot=card-action: gap=8");
		// (data-size and a group's select the rule's size, data-variant its variant)
		same("data-[size=sm]:h-3.5 group-data-[size=default]/switch:size-4 data-[variant=destructive]:text-destructive",
			"x(default) width=16 height=16\nx(sm) height=14\nx[destructive] color=var(--destructive)");
		same("bg-primary hover:bg-primary/90", "x[default] background=var(--primary)\nx[default] hover: background=var(--primary)/90", "default");
		same("h-8 px-3", "x(sm) height=32 padding=0 12 0 12", null, "sm");
		same("md:text-sm text-base", "x fontSize=16 lineHeight=1.5\nx md: fontSize=14 lineHeight=1.4286");
	}

	static function shorthands() {
		// (the sides a rule leaves out are those of the rules holding with it)
		same("px-4 py-2 hover:px-6", "x padding=8 16 8 16\nx hover: padding=8 24 8 24");
		same("rounded-md border hover:rounded-t-none hover:border-b-2", "x corners=8 borders=1\nx hover: corners=0 0 8 8 borders=1 1 2 1");
		same("text-sm hover:leading-6", "x fontSize=14 lineHeight=1.4286\nx hover: lineHeight=1.7143");
		same("translate-x-1 data-[state=open]:translate-y-1", "x transform=translateX(4px)\nx data-state=open: transform=translateX(4px) translateY(4px)");
		same("flex flex-col md:flex", "x display=Flex direction=Column\nx md: display=Flex");
	}

	static function more() {
		// (rings and outlines apart, as CSS draws them; outline-none: no focus ring of the window's either)
		same("focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-1 focus-visible:outline-ring",
			"x focus-visible: ringWidth=3 ringColor=var(--ring)/50 outlineWidth=1 outlineStyle=Solid outlineColor=var(--ring)");
		same("outline-2 outline-offset-2 outline-ring", "x outlineWidth=2 outlineStyle=Solid outlineOffset=2 outlineColor=var(--ring)");
		same("outline-none", "x outlineStyle=None");
		same("outline-hidden", "x outlineStyle=None");
		same("fill-primary shadow-[0_4px_12px_rgba(0,0,0,0.1)] leading-[1.4]", "x color=var(--primary) shadow=0 4 12 0 rgba(0,0,0,0.1) lineHeight=1.4");
		same("*:data-[slot=select-value]:flex **:data-[slot=x]:h-12 after:absolute rtl:**:[.rdp-button]:rotate-180", "");
		same("max-h-(--radix-select-content-available-height) origin-(--radix-popover-content-transform-origin)", "");
		// (CSS variables from the sheet: calendar's --cell-size)
		var tw = new Tailwind(10, (m, _, _) -> throw m, ["--cell-size" => "2rem"]);
		var got = tw.slot("x", [{classes: "size-(--cell-size) px-(--cell-size)", offset: 0}]).map(Tailwind.describe).join("\n");
		check("vars", got == "x width=32 height=32 padding=0 32 0 32", got);
		// (a class list after a size's, as cn's className after cva's: later than it)
		got = tw.slot("x", [
			{classes: "h-9 px-4", offset: 0},
			{classes: "h-8 px-2", offset: 0, size: "sm"},
			{classes: "px-3", offset: 0}
		]).map(Tailwind.describe).join("\n");
		check("className after cva", got == "x height=36 padding=0 16 0 16\nx(sm) height=32 padding=0 8 0 8\nx padding=0 12 0 12", got);
	}

	static function motion() {
		same("transition-all", "x transition=all 150ms cubic-bezier(0.4,0,0.2,1)");
		same("transition-[color,box-shadow] duration-200 ease-out",
			"x transition=color 200ms cubic-bezier(0,0,0.2,1), shadow 200ms cubic-bezier(0,0,0.2,1)");
		same("transition-none", "x transition=all 0s");
		same("duration-300", "x transition=all 300ms cubic-bezier(0.4,0,0.2,1)");
		// (animate-in: opacity and transform eased from the starting state; a side's slide and the zoom composed)
		same("data-[state=open]:animate-in data-[state=open]:fade-in-0 data-[state=open]:zoom-in-95 data-[side=bottom]:slide-in-from-top-2",
			"x data-state=open: transition=opacity 150ms ease, transform 150ms ease\n"
			+ "x data-state=open starting: opacity=0 transform=scale(0.95)\n"
			+ "x data-side=bottom starting: transform=translateY(-8px)\n"
			+ "x data-state=open starting data-side=bottom: transform=translateY(-8px) scale(0.95)");
		same("transition ease-in-out data-[state=open]:animate-in data-[state=open]:duration-500 data-[state=open]:slide-in-from-right",
			"x transition=color 150ms cubic-bezier(0.4,0,0.2,1), background 150ms cubic-bezier(0.4,0,0.2,1), borderColor 150ms cubic-bezier(0.4,0,0.2,1), "
			+ "outlineColor 150ms cubic-bezier(0.4,0,0.2,1), textDecorationColor 150ms cubic-bezier(0.4,0,0.2,1), opacity 150ms cubic-bezier(0.4,0,0.2,1), "
			+ "shadow 150ms cubic-bezier(0.4,0,0.2,1), transform 150ms cubic-bezier(0.4,0,0.2,1)\n"
			+ "x data-state=open: transition=color 500ms cubic-bezier(0.4,0,0.2,1), background 500ms cubic-bezier(0.4,0,0.2,1), borderColor 500ms cubic-bezier(0.4,0,0.2,1), "
			+ "outlineColor 500ms cubic-bezier(0.4,0,0.2,1), textDecorationColor 500ms cubic-bezier(0.4,0,0.2,1), opacity 500ms cubic-bezier(0.4,0,0.2,1), "
			+ "shadow 500ms cubic-bezier(0.4,0,0.2,1), transform 500ms cubic-bezier(0.4,0,0.2,1), opacity 500ms cubic-bezier(0.4,0,0.2,1), transform 500ms cubic-bezier(0.4,0,0.2,1)\n"
			+ "x data-state=open starting: transform=translateX(100%)");
		same("selection:bg-primary rtl:pl-2 md:p-1", "x selection: background=var(--primary)\nx md: padding=4\nx rtl: padding=0 0 0 8");
	}

	static function ignored() {
		same("select-none peer group/switch @container/card-header text-current animate-out fade-out-0 zoom-out-95 animate-pulse", "");
		same("[&_svg]:size-4 [&_svg:not([class*='size-'])]:size-4 has-[>svg]:px-3 [a&]:hover:bg-accent [.border-b]:pb-6 file:h-7", "");
		rejected("foo-bar", "unknown class foo-bar");
		rejected("bg-blue-500", "unknown class bg-blue-500");
		rejected("hover:p-wat", "unknown class hover:p-wat");
		rejected("wat:p-2", "unknown variant wat: in wat:p-2");
		rejected("mx-[auto]", "unknown class mx-[auto]");
		rejected("w-[calc(100%-2rem)]", "unknown class w-[calc(100%-2rem)]");
	}

	// (Tw's rules at compile time: object literals of StyleProps)
	static function macro_() {
		var r = Tw.rules("button", "h-9 px-4 rounded-md hover:opacity-90 data-[size=sm]:h-8", "default");
		check("Tw.rules: 3 rules", r.length == 3, '${r.length}');
		check("Tw.rules: base", r[0].slot == "button" && r[0].variant == "default" && r[0].when == null && Type.enumEq(r[0].style.height, Px(36))
			&& r[0].style.radius == 8 && r[0].style.padding.left == 16 && r[0].style.padding.top == 0);
		check("Tw.rules: hover", r[1].when[0] == "hover" && r[1].style.opacity == 0.9);
		check("Tw.rules: size", r[2].size == "sm" && Type.enumEq(r[2].style.height, Px(32)));
	}

	static function sheet() {
		var s = Shadcn.sheet;
		check("sheet: rules", s.rules.length > 50, '${s.rules.length}');
		check("sheet: tokens", s.light["primary"] != null && s.dark["primary"] != null && s.light.get("primary") != s.dark.get("primary"));
		Sys.println('ThemeTest: Shadcn.sheet: ${s.rules.length} rules');
	}

	static function rejects(tool:String, dir:String) {
		var files = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".hx")) f];
		files.sort(Reflect.compare);
		for (f in files) {
			var content = sys.io.File.getContent('$dir/$f');
			var expect = [
				for (l in content.split("\n"))
					if (StringTools.startsWith(l, "// expect: ")) StringTools.trim(l.substr(11))
			];
			var args = [
				"-cp", "packages/ui/src", "-cp", "packages/theme/src", "-cp", dir, "-main", f.substr(0, f.length - 3),
				"--interp", "--no-output"
			];
			var p = new sys.io.Process(tool, args);
			var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
			var code = p.exitCode();
			p.close();
			var missing = [for (e in expect) if (out.indexOf(e) < 0) e];
			check('reject/$f', code != 0 && expect.length > 0 && missing.length == 0,
				code == 0 ? "compiled, but must be rejected" : "missing: " + missing.join("; ") + "\n" + out);
		}
	}
}
