import Model;
import helder.asset.Asset;
import helder.text.FontFile;
import helder.ui.*;
import helder.ui.widgets.Theme;
import helder.ui.widgets.Theme.c;
import helder.ui.view.UiFlow.Popover;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// Where a font starts: Pebble (Foundry's own, pen lines), an open font's
// own outlines (Outlines: Inter, Hanken Grotesk, Geist Mono, each under
// the SIL Open Font License, as what is made from it stays), a font file
// of the user's (desktop), or nothing. Each card set in its own font.
class Start implements Markup {
	public static inline var PEBBLE = "Foundry Pebble";

	static final STARTERS:Array<Starter> = [
		{
			id: "pebble",
			name: "Pebble",
			about: "A round monoline sans drawn in Foundry: about fifty letters, the rest borrowed.",
			family: PEBBLE,
			license: "Foundry's own, MIT"
		},
		{
			id: "inter",
			name: "Inter",
			about: "A neutral grotesk for screens by Rasmus Andersson, its outlines as they are.",
			family: "Inter",
			license: "SIL Open Font License 1.1",
			file: () -> Asset.embed("fonts/Inter.ttf")
		},
		{
			id: "hanken",
			name: "Hanken Grotesk",
			about: "A friendly geometric grotesk by Alfredo Marco Pradil, its outlines as they are.",
			family: "Hanken Grotesk",
			license: "SIL Open Font License 1.1",
			file: () -> Asset.embed("fonts/HankenGrotesk-Regular.ttf")
		},
		{
			id: "geist",
			name: "Geist Mono",
			about: "A monospace by Vercel, every letter as wide as the next, its outlines as they are.",
			family: "Geist Mono",
			license: "SIL Open Font License 1.1",
			file: () -> Asset.embed("fonts/GeistMono-Regular.ttf")
		}
	];

	// the faces the cards are set in that are not the system's: Pebble's
	public static function fonts()
		try helder.text.SystemFonts.get().add(Draft.encode(Sample.face(), PEBBLE)) catch (_:Dynamic) {}

	public static function view(ws:Workshop):View {
		var busy = signal("");
		function pick(s:Starter) {
			if (busy.peek() != "") return;
			busy(s.id);
			// (a frame drawn first, to show which is being traced)
			var frames = 0;
			Clock.add(_ -> {
				if (++frames < 3) return true;
				var face = s.file == null ? Sample.face() : Outlines.face(FontFile.parse(s.file()), "My " + s.name);
				busy("");
				ws.begin(face);
				ws.say(s.file == null ? 'Started from ${s.name}' : 'Started from ${s.name}\'s outlines, ${countDrawn(face)} letters: ${s.license}');
				return false;
			});
		}
		function blank() {
			ws.begin(Model.empty("My Font"));
			ws.say("A blank font: trace the grey letter behind each one, or draw your own");
		}
		function open() {
			var path = helder.os.FileDialog.open(helder.os.App.windows[0], "Open a font", [{name: "Fonts", extensions: ["ttf", "otf"]}]);
			if (path == null) return;
			try {
				var face = Outlines.face(FontFile.parse(sys.io.File.getBytes(path)), "My Font");
				ws.begin(face);
				ws.say('Started from ${haxe.io.Path.withoutDirectory(path)}: keep to its license when you share what you make');
			} catch (e:Dynamic) {
				ws.say('Could not read that font ($e)');
			}
		}
		return <Popover open={ws.starting} modal placement="center" backdrop={Color.rgba(0, 0.5)} onDismiss={() -> ws.starting(false)}>
			<view tag="start" role="dialog" label="Start a font" width={860} padding={28} row-gap={20} radius={Theme.RADIUS_M + 4} background={c("bg")}
				border-width={1} border-color={c("edge")} shadow={Theme.popover()}>
				<view row-gap={6}>
					<text font-size={22} font-weight={Theme.MEDIUM}>Start a font</text>
					<text color={c("fg2")}>Pick where to begin. Every letter stays yours to redraw: the pen, the proportions and the spacing too.</text>
				</view>
				<view display="grid" grid-template-columns="repeat(4, 1fr)" column-gap={12}>
					<For each={STARTERS}>{(s:Read<Starter>) -> card(s(), busy, pick)}</For>
				</view>
				<view direction="row" align-items="center" column-gap={8}>
					<view:button tag="start-blank" slot="button" role="button" label="Start blank" focusable onPress={blank}>
						<image src={Icons.pen} width={14} height={14}/><text>Start blank</text>
					</view:button>
					<Show when={helder.os.FileDialog.available()}>
						<view:button tag="start-file" slot="button" role="button" label="Open a font file" focusable onPress={open}>
							<image src={Icons.download} width={14} height={14}/><text>Open a font file…</text>
						</view:button>
					</Show>
					<view grow={1}/>
					<text font-size={Theme.SMALL} color={c("fg3")}>A font made from an OFL font is shared under the OFL too.</text>
				</view>
			</view>
		</Popover>;
	}

	static function card(s:Starter, busy:Read<String>, pick:Starter->Void):View
		return <view:button tag={"start-" + s.id} slot="starter" role="button" label={"Start from " + s.name} focusable onPress={() -> pick(s)}>
			<view height={120} align-items="center" justify="center" radius={Theme.RADIUS_M} background={c("well")}>
				<Show when={busy() == s.id} fallback={<text font-family={s.family} font-size={58} line-height="64px" color={c("fg")}>Ag</text>}>
					<text color={c("fg2")}>Reading…</text>
				</Show>
			</view>
			<view row-gap={4} padding="10 2 0">
				<text font-weight={Theme.MEDIUM}>{s.name}</text>
				<text font-size={Theme.SMALL} color={c("fg2")} line-height="16px">{s.about}</text>
				<text font-size={10} color={c("fg3")} padding="4 0 0">{s.license}</text>
			</view>
		</view:button>;

	static function countDrawn(f:Face):Int
		return [for (k in f.glyphs.keys()) k].length;
}

private typedef Starter = {id:String, name:String, about:String, family:String, license:String, ?file:Void->haxe.io.Bytes};
