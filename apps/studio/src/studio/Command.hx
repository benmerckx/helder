package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Theme.c;

using StringTools;

// The command field's list (secondary-K, the toolbar's field): a frame, a
// file or a tool by name, what is typed matching the words in order
// (Command.matches); Enter takes the one marked (the arrows move it), a
// click any, Escape or a click outside closes it. Later the prompt's too.
class Command implements Markup {
	public static function view(studio:Studio):View {
		var query = signal(""), at = signal(0);
		function pick(i:Item) {
			studio.commandOpen(false);
			i.run();
		}
		function shown():Array<Item> {
			var q = query();
			return [for (i in items(studio)) if (matches(i.label + " " + i.detail, q)) i].slice(0, 12);
		}
		return <view tag="command-layer" position="absolute" inset={0} onClick={_ -> studio.commandOpen(false)}>
			<view tag="command-list" slot="floating" position="absolute" top={Theme.HEADER + 4} left={left(studio)} width={480} padding={6}
				shadow="0 16 48 rgba(0,0,0,0.5)" transition="fade scale" motion="snappy" onClick={e -> e.stop()}>
				<view direction="row" align-items="center" column-gap={8} height={36} padding="0 8" border-width="0 0 1 0" border-color={c("line")}>
					<image src={Icons.search} width={Theme.ICON} height={Theme.ICON} color={c("fg3")}/>
					<field tag="command-input" slot="ask-input" label="Jump to" value={query} placeholder="A frame, a file or a tool…"
						ref={(n:Node) -> haxe.Timer.delay(() -> n.focus(), 0)} onInput={e -> {
							query(e.text);
							at(0);
						}} onKeyDown={e -> {
							var list = shown();
							if (e.key == Key.DOWN) at(Std.int(Math.min(list.length - 1, at.peek() + 1)));
							if (e.key == Key.UP) at(Std.int(Math.max(0, at.peek() - 1)));
							if (e.key == Key.ENTER && list.length > 0) pick(list[Std.int(Math.min(at.peek(), list.length - 1))]);
						}}/>
				</view>
				<view padding="6 0 0" row-gap={1}>
					<For each={shown()}>{(i:Read<Item>) ->
						<view:button tag={"command-" + Shell.slug(i().label)} slot="menu-item" role="button" label={i().label}
							data-on={shown().indexOf(i()) == at() ? "true" : "false"} onPress={() -> pick(i())}>
							<image src={i().icon} width={Theme.ICON_S} height={Theme.ICON_S} color={c("fg3")}/>
							<text grow={1} max-lines={1} text-overflow="ellipsis">{i().label}</text>
							<text font-size={Theme.SMALL} color={c("fg3")} max-lines={1}>{i().detail}</text>
						</view:button>
					}</For>
				</view>
			</view>
		</view>;
	}

	static function left(studio:Studio):Float {
		studio.stageSize();
		var i = studio.insets();
		return Math.max(Theme.GAP, i.left + (studio.stageWidth - i.left - i.right - 480) / 2);
	}

	// the frames, the files, the tools
	static function items(studio:Studio):Array<Item> {
		var out:Array<Item> = [], p = studio.project;
		if (p == null) return out;
		for (s in p.screens)
			out.push({label: s.label, detail: s.flow, icon: Icons.frame, run: () -> {
				if (studio.mode() == "stories") studio.setMode("design");
				studio.focus(s.name);
			}});
		for (f in p.sources())
			out.push({label: haxe.io.Path.withoutDirectory(f), detail: Shell.fileLabel(studio, f), icon: f.endsWith(".helder") ? Icons.penTool : Icons.fileCode,
				run: () -> studio.openCode(f)});
		out.push({label: "Zoom to fit", detail: "Shift 1", icon: Icons.scan, run: () -> studio.fitAll()});
		out.push({label: "Zoom to selection", detail: "Shift 2", icon: Icons.maximize, run: () -> studio.fitSelection()});
		out.push({label: "Design", detail: "the canvas", icon: Icons.penTool, run: () -> studio.setMode("design")});
		out.push({label: "Code", detail: "the code view", icon: Icons.code, run: () -> studio.setMode("code")});
		out.push({label: "Stories", detail: "every story", icon: Icons.bookOpen, run: () -> studio.setMode("stories")});
		out.push({label: "Check the program", detail: "/check", icon: Icons.sparkles, run: () -> studio.ask("/check")});
		return out;
	}

	// whether every word of q is in text, in order, ignoring case
	public static function matches(text:String, q:String):Bool {
		var t = text.toLowerCase(), at = 0;
		for (w in q.toLowerCase().split(" ")) {
			if (w == "") continue;
			var i = t.indexOf(w, at);
			if (i < 0) return false;
			at = i + w.length;
		}
		return true;
	}
}

@:structInit class Item {
	public final label:String;
	public final detail:String;
	public final icon:helder.ui.Svg;
	public final run:Void->Void;
}
