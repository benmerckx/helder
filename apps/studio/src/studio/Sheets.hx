package studio;

import helder.ui.*;
import helder.ui.gesture.Gesture;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import studio.Theme.c;

// Compact (a phone, a tablet upright): the canvas always underneath (a
// finger pans, two pinch, a tap selects, a double tap enters), the
// desktop's panels as sheets over it, one at a time: the files and layers
// (Shell's sidebar), the inspector (Inspector's card), the code (the code
// view), the prompt; a bar at the bottom switches between them. A sheet
// rests at a detent (peek, half, full), dragged by its handle (let go: the
// nearest detent; flung down past peek, away), the handle tapped goes up a
// detent; the canvas fits what is in focus above it (the code at half
// leaves the frame in view, an edit seen landing).
class Sheets implements Markup {
	public static final names = ["files", "inspect", "code", "ask"];
	// (a story's controls while it plays: a sheet of its own, opened from the top bar, not the bar)

	static function label(n:String):String
		return switch n {
			case "files": "Files";
			case "inspect": "Inspect";
			case "code": "Code";
			case "controls": "Controls";
			case _: "Ask";
		}

	static function icon(n:String):Svg
		return switch n {
			case "files": Icons.folder;
			case "inspect": Icons.ruler;
			case "code": Icons.code;
			case _: Icons.sparkles;
		}

	// the bar switching the sheets
	public static function bar(studio:Studio):View
		return <view tag="sheet-bar" position="absolute" left={0} right={0} bottom={0} height={Theme.BAR} direction="row" align-items="center"
			justify="center" column-gap={4} padding="0 8" background={c("bg")} border-width="1 0 0 0" border-color={c("line")}>
			{[for (n in names) <view:button tag={"tab-" + n} role="button" label={label(n)} focusable grow={1} max-width={96} height={Theme.BAR - 12} radius={Theme.RADIUS_M}
				align-items="center" justify="center" row-gap={2} cursor="pointer" color={studio.sheet() == n ? c("accent-ink") : c("fg3")}
				background={studio.sheet() == n ? c("on") : null} onPress={() -> studio.openSheet(n)}>
				<image src={icon(n)} width={Theme.ICON} height={Theme.ICON}/>
				<text font-size={Theme.CAPS}>{label(n)}</text>
			</view:button>]}
		</view>;

	// the sheet open, at its detent (or where the handle is while dragged)
	public static function view(studio:Studio):View {
		var dragged = signal(0.0);
		return <view tag={"sheet-" + studio.sheet()} slot="sheet" position="absolute" left={0} right={0} bottom={studio.playing() != null ? 0 : Theme.BAR}
			height={Math.max(24, studio.sheetHeight(studio.detent()) - dragged())} border-width="1 0 0 0" overflow="hidden" shadow={Theme.SHEET_SHADOW}
			transition="slide-up(80)" motion="snappy" instant={dragged() != 0} onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<view tag="sheet-handle" height={24} shrink={0} instant align-items="center" justify="center" cursor="grab"
				onClick={_ -> studio.raiseSheet()} onPan={(g:Gesture) -> switch g.state {
					case Began | Changed: dragged(g.ty);
					case Ended:
						var h = studio.sheetHeight(studio.detent.peek()) - g.ty;
						dragged(0);
						studio.settleSheet(h, g.vy);
					case _: dragged(0);
				}}>
				<view slot="sheet-handle"/>
			</view>
			<view grow={1} min-height={0} instant>{content(studio, studio.sheet())}</view>
		</view>;
	}

	static function content(studio:Studio, n:Null<String>):View
		return switch n {
			case "files": Shell.sidebar(studio, false);
			case "inspect": Inspector.card(studio);
			case "code": <view grow={1} min-height={0}>
					<view direction="row" align-items="center" column-gap={6} height={Theme.ROW + 6} padding={'0 ${Theme.PAD}'} shrink={0} font-size={Theme.SMALL} color={c("fg2")}>
						<image src={Icons.fileCode} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("kind-code")}/>
						<text tag="code-file" font-family={Theme.CODE} max-lines={1}>{Shell.fileLabel(studio, studio.codeFile())}</text>
					</view>
					{studio.editor}
				</view>;
			case "ask": ask(studio);
			case "controls": Play.controls(studio);
			case _: null;
		}

	// the prompt: its line, the agent's last reply under it
	static function ask(studio:Studio):View {
		var text = signal("");
		function send() {
			studio.ask(text.peek());
			text("");
		}
		return <view padding={'0 ${Theme.PAD} 10'} row-gap={8}>
			<view direction="row" align-items="center" column-gap={8} height={36} padding="0 10" radius={Theme.RADIUS_M} background={c("well")}>
				<image src={Icons.sparkles} width={Theme.ICON} height={Theme.ICON} color={c("accent")}/>
				<field tag="prompt" slot="ask-input" label="Prompt" value={text} placeholder={studio.context().label} onInput={e -> text(e.text)}
					onKeyDown={e -> if (e.key == Key.ENTER) send()}/>
			</view>
			<text tag="ask-reply" color={c("fg3")} font-size={Theme.SMALL}>{studio.reply()}</text>
		</view>;
	}
}
