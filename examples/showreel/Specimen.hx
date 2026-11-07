import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// Type set at many sizes: Inter's variable weight axis swept on a glyph
// pair three hundred points tall (helder.text's outlines, its avar and
// gvar deltas applied), a waterfall of a line from 13 to 60 points coming
// in, and a paragraph justified, its figures tabular.
class Specimen implements Markup {
	public static final scene:SceneDef = {name: "type", title: "Type at every size", duration: 7.0, view: view};

	static final SIZES = [13, 17, 23, 32, 44, 60];

	// the swept weight at t (steps of 10: the glyphs kept in the atlas)
	static function weight(t:Float):Int {
		var w = 100 + 800 * (0.5 - 0.5 * Math.cos(Math.max(0, t - 0.4) * 1.7));
		return Std.int(Math.round(w / 10) * 10);
	}

	public static function view(t:Read<Float>):View {
		return <view grow={1} direction="row" padding="44 56" column-gap={56} background={NIGHT} color={INK} font-family="Inter">
			<view width={430} row-gap={10} justify="center">
				<text font-size={14} color={MUTED} font-weight={600} letter-spacing={1.6}>INTER · VARIABLE</text>
				<text font-family="Inter Display" font-size={300} line-height={1.18} letter-spacing={-12} font-weight={weight(t())}>Ag</text>
				<view direction="row" align-items="center" column-gap={12}>
					<text font-size={15} color={MUTED} font-variant-numeric="tabular-nums">{"wght " + weight(t())}</text>
					<view grow={1} height={2} radius={1} background={LINE}>
						<view height={2} radius={1} background={VIOLET} width={((weight(t()) - 100) / 8) + "%"}/>
					</view>
				</view>
			</view>
			<view grow={1} min-width={0} justify="center" row-gap={14}>
				<Repeat count={6}>{i -> <Show when={() -> at(t(), 0.3 + i * 0.22)}>
					<view direction="row" align-items="baseline" column-gap={16} transition="fade slide-up(18)">
						<text width={36} font-size={12} color={MUTED} font-variant-numeric="tabular-nums">{SIZES[i] + "pt"}</text>
						<text grow={1} min-width={0} font-family={SIZES[i] >= 32 ? "Inter Display" : "Inter"} font-size={SIZES[i]} font-weight={SIZES[i] >= 44 ? 700 : 500}
							letter-spacing={SIZES[i] >= 32 ? -SIZES[i] * 0.025 : 0} text-wrap="nowrap" text-overflow="ellipsis">Sphinx of black quartz</text>
					</view>
				</Show>}</Repeat>
				<Show when={() -> at(t(), 2.0)}>
					<view row-gap={10} padding="18 0 0 0" transition="fade slide-up(18)">
						<view height={1} background={LINE}/>
						<text font-size={15} line-height={1.6} color={MUTED} text-align="justify">Glyphs are shaped and rasterised by helder.text, the same pixels on every platform, then drawn by the UI in one call with everything else on screen. Figures can be tabular when they line up in columns: 1,204.50 · 98.10 · 31,007.00.</text>
					</view>
				</Show>
			</view>
		</view>;
	}
}
