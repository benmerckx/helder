package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import studio.Theme.c;

// The prompt bar under the canvas: what it asks about follows what is in
// focus ("Ask about the whole app…", "Ask about Hangar…"); a prompt goes
// to the studio's agent (Agent: the interface a hosted prompt box plugs
// into; for now LocalAgent, no model: "/tree", "/check", "/snap", "/read"
// call the studio's own tools, Tools, the MCP server's).
class Prompt implements Markup {
	public static function view(studio:Studio):View {
		var text = signal("");
		function send() {
			studio.ask(text.peek());
			text("");
		}
		return <view tag="ask" slot="ask" position="absolute" bottom={14} left={left(studio)} width={width(studio)} padding="10 10 8 14" row-gap={8}
			onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<field tag="prompt" slot="field-input" font-family={Theme.UI} font-size={Theme.BODY} label="Prompt" value={text}
				placeholder={studio.context().label} onInput={e -> text(e.text)} onKeyDown={e -> if (e.key == Key.ENTER) send()}/>
			<view direction="row" align-items="center" column-gap={12} font-size={12} color={c("fg2")}>
				<view tag="ask-context" direction="row" align-items="center" column-gap={6} padding="2 7" shrink={0} radius={Theme.R1} background={c("well")}>
					<view width={6} height={6} radius={3} background={studio.focused() == null ? c("fg3") : c("k-screen")}/>
					<text max-lines={1}>{studio.context().scope}</text>
				</view>
				<text tag="ask-reply" grow={1} color={c("fg3")} max-lines={1} text-overflow="ellipsis">{studio.reply()}</text>
				<view:button tag="ask-send" role="button" label="Send" focusable width={26} height={26} radius={Theme.R1} background={c("hover")}
					align-items="center" justify="center" color={c("fg2")} cursor="pointer" onPress={() -> send()}>
					<image src={Icons.send} width={14} height={14}/>
				</view:button>
			</view>
		</view>;
	}

	static function width(studio:Studio):Float {
		studio.stageSize();
		return Math.min(Theme.ASK, studio.stageWidth * 0.72);
	}

	static function left(studio:Studio):Float {
		studio.stageSize();
		return (studio.stageWidth - width(studio)) / 2;
	}
}
