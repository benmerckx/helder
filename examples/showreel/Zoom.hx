import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// A matched-element zoom: the gallery's photos (painted by Photos.hx) are
// matched="photo-<n>"; one picked leaves the grid and the same id is laid
// out across the stage, so it flies from where it was seen, its radius
// and frame with it, its picture scaled to cover the frame as it goes;
// the caption rides in beside it. Then back, and another.
class Zoom implements Markup {
	public static final scene:SceneDef = {name: "zoom", title: "A matched zoom", duration: 7.5, view: view};

	// the photo shown large at t (-1: the grid)
	static function open(t:Float):Int
		return t >= 1.3 && t < 3.5 ? 1 : t >= 4.3 && t < 6.6 ? 5 : -1;

	static function Photo(props:{i:Int, big:Bool}):View
		return <view tag={"photo-" + props.i} matched={"photo-" + props.i} grow={1} basis={0} min-width={0} min-height={0} radius={props.big ? 24 : 16} overflow="hidden" background={RAISED}>
			<image src={Photos.images[props.i]} fit="cover" grow={1} min-width={0} min-height={0}/>
		</view>;

	static function Tile(props:{t:Read<Float>, i:Int}):View
		return <view grow={1} basis={0} min-width={0} min-height={0} row-gap={10}>
			<Photo i={props.i} big={false}/>
			<view direction="row" align-items="baseline" column-gap={8}>
				<text font-size={14} font-weight={600} grow={1}>{Photos.PLACES[props.i].title}</text>
				<text font-size={12} color={MUTED}>{"No. " + (props.i + 1)}</text>
			</view>
		</view>;

	static function Grid(props:{t:Read<Float>}):View
		return <view grow={1} row-gap={22} transition="fade">
			<view direction="row" grow={1} column-gap={22}>
				<Repeat count={3}>{i -> <Show when={() -> at(props.t(), 0.1 + i * 0.1)}><view grow={1} basis={0} min-width={0} transition="fade pop"><Tile t={props.t} i={i}/></view></Show>}</Repeat>
			</view>
			<view direction="row" grow={1} column-gap={22}>
				<Repeat count={3}>{i -> <Show when={() -> at(props.t(), 0.4 + i * 0.1)}><view grow={1} basis={0} min-width={0} transition="fade pop"><Tile t={props.t} i={i + 3}/></view></Show>}</Repeat>
			</view>
		</view>;

	static function Large(props:{i:Int}):View {
		var p = Photos.PLACES[props.i];
		return <view grow={1} direction="row" column-gap={28}>
			<Photo i={props.i} big={true}/>
			<view width={300} justify="end" row-gap={12} padding="0 0 12 0" transition="fade slide-left(40)">
				<text font-size={13} color={MUTED} letter-spacing={1.6} font-weight={600}>{"PLATE " + (props.i + 1) + " OF 6"}</text>
				<text font-family="Inter Display" font-size={40} font-weight={700} line-height={1.05} letter-spacing={-1}>{p.title}</text>
				<text font-size={15} color={MUTED} font-variant-numeric="tabular-nums">{p.meta}</text>
				<view height={1} background={LINE} margin="8 0"/>
				<text font-size={14} color={MUTED} line-height={1.5}>Painted with helder.canvas when the reel starts: a sky's gradient, a sun's glow and five ridges of sines fading into the haze.</text>
			</view>
		</view>;
	}

	public static function view(t:Read<Float>):View {
		var shown = () -> open(t());
		return <view grow={1} padding="40 48" row-gap={24} background={NIGHT} color={INK} font-family="Inter" motion="default">
			<view direction="row" align-items="baseline" column-gap={14}>
				<text font-family="Inter Display" font-size={30} font-weight={700} letter-spacing={-0.6}>Field notes</text>
				<text font-size={15} color={MUTED}>six plates · matched="photo-n"</text>
			</view>
			<view grow={1} min-height={0}>
				<Show when={() -> shown() < 0} fallback={<view grow={1}>{() -> <Large i={shown()}/>}</view>}>
					<Grid t={t}/>
				</Show>
			</view>
		</view>;
	}
}
