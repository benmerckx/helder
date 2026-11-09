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
// call the studio's own tools, Tools, the MCP server's). One line: the
// prompt, the agent's last reply after it.
class Prompt implements Markup {
	public static function view(studio:Studio):View {
		var text = signal("");
		function send() {
			studio.ask(text.peek());
			text("");
		}
		return <view tag="ask" slot="floating" position="absolute" bottom={Theme.PAD} left={left(studio)} width={width(studio)} direction="row" align-items="center"
			column-gap={8} height={34} padding="0 10" onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<image src={Icons.sparkles} width={Theme.ICON_S} height={Theme.ICON_S} color={c("accent-ink")}/>
			<field tag="prompt" slot="ask-input" label="Prompt" value={text} placeholder={studio.context().label} onInput={e -> text(e.text)}
				onKeyDown={e -> if (e.key == Key.ENTER) send()}/>
			<text tag="ask-reply" shrink={1} min-width={0} max-width="50%" color={c("fg3")} font-size={Theme.SMALL} max-lines={1}
				text-overflow="ellipsis">{studio.reply()}</text>
		</view>;
	}

	// (centred between the panels)
	static function width(studio:Studio):Float {
		studio.stageSize();
		var i = studio.insets();
		return Math.min(Theme.ASK, (studio.stageWidth - i.left - i.right) * (studio.compact() ? 0.92 : 0.8));
	}

	static function left(studio:Studio):Float {
		studio.stageSize();
		var i = studio.insets();
		return i.left + (studio.stageWidth - i.left - i.right - width(studio)) / 2;
	}
}
