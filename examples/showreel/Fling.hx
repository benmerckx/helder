import Reel.*;
import Reel.SceneDef;
import helder.ui.VirtualScroll;
import helder.ui.view.UiFlow.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// A million rows flung end to end: a VirtualList (only the rows in view
// made, a sum tree of the rest's heights) scrolled by the scene's clock,
// a long glide down to the last row, a rest, and back up to the first;
// beside it the row at the top and the rail of where that is among a
// million.
class Fling implements Markup {
	public static final scene:SceneDef = {name: "million", title: "A million rows, flung", duration: 7.0, view: view};

	static inline var COUNT = 1000000;
	static inline var ROW = 56;

	static final NAMES = ["Ada Okafor", "Grace Lindqvist", "Linus Moreau", "Margaret Sato", "Ken Adeyemi", "Barbara Novak", "Dennis Ivanova", "Frances Kim",
		"Alan Duarte", "Radia Haddad", "Edsger Byrne", "Hedy Castillo", "Joan Mbeki", "Tim Okonkwo", "Sophie Wilson", "Lynn Conway"];
	static final WHAT = ["Invoice paid", "Order shipped", "Refund issued", "Subscription renewed", "Payout sent", "Card authorised", "Transfer received", "Order placed"];
	static final COLORS = [BLUE, VIOLET, MINT, AMBER, CORAL, "#4cc9f0", "#f4a261", "#90be6d"];

	static final items:Signal<Array<Int>> = signal([for (i in 0...COUNT) i]);

	// where the list is at t: rows from the top (fractional)
	static function position(t:Float):Float {
		var span = COUNT - 10.5;
		if (t < 0.9) return 0;
		if (t < 3.6) return span * inOut(lin(t, 0.9, 3.6));
		if (t < 4.3) return span;
		return span * (1 - inOut(lin(t, 4.3, 6.6)));
	}

	static function Row(props:{id:Read<Int>}):View {
		var id = untrack(() -> props.id());
		var h = hash(id + 11), name = NAMES[h % NAMES.length], amount = (h % 90000) / 100 + 4;
		return <view tag="row" direction="row" align-items="center" column-gap={14} height={ROW} padding="0 20" border-width="0 0 1 0" border-color={LINE}>
			<text width={78} font-size={13} color={MUTED} font-variant-numeric="tabular-nums">{thousands(id + 1)}</text>
			<view width={30} height={30} radius={15} align-items="center" justify="center" background={COLORS[h % COLORS.length]}>
				<text font-size={12} font-weight={700} color={NIGHT}>{name.charAt(0) + name.charAt(name.indexOf(" ") + 1)}</text>
			</view>
			<view grow={1} min-width={0}>
				<text font-size={15} font-weight={550}>{name}</text>
				<text font-size={13} color={MUTED}>{WHAT[(h >> 4) % WHAT.length]}</text>
			</view>
			<text font-size={15} font-weight={600} font-variant-numeric="tabular-nums">{"€" + Std.string(Math.floor(amount)) + "." + StringTools.lpad(Std.string(Math.round(amount * 100) % 100), "0", 2)}</text>
		</view>;
	}

	public static function view(t:Read<Float>):View {
		var list:Null<VirtualScroll> = null;
		effect(() -> position(t()), p -> if (list != null) list.scrollY = p * ROW);
		var top = () -> Std.int(position(t())) + 1;
		return <view grow={1} direction="row" padding="40 48" column-gap={48} background={NIGHT} color={INK} font-family="Inter">
			<view width={640} radius={20} overflow="hidden" background={PANEL} border-width={1} border-color={LINE}>
				<view direction="row" align-items="center" padding="16 20" border-width="0 0 1 0" border-color={LINE}>
					<text grow={1} font-size={16} font-weight={650}>Ledger</text>
					<text font-size={13} color={MUTED}>1,000,000 entries</text>
				</view>
				<VirtualList tag="ledger" each={items} itemHeight={ROW} label="Ledger" ref={l -> list = l}>{(id:Read<Int>, i:Int) -> <Row id={id}/>}</VirtualList>
			</view>
			<view grow={1} justify="center" row-gap={18}>
				<text font-size={14} color={MUTED} font-weight={600} letter-spacing={1.6}>ROW AT THE TOP</text>
				<text font-family="Inter Display" font-size={84} font-weight={700} letter-spacing={-2} line-height={1} font-variant-numeric="tabular-nums">{thousands(top())}</text>
				<text font-size={18} color={MUTED}>of 1,000,000 · only the rows in view are made</text>
				<view height={8} radius={4} background={LINE} margin="18 0 0 0">
					<view height={8} radius={4} width={(Math.max(1.5, position(t()) / (COUNT - 10.5) * 100)) + "%"} background="linear-gradient(90deg, #6d8bff, #3ee0a8)"/>
				</view>
				<view direction="row">
					<text grow={1} font-size={13} color={MUTED}>1</text>
					<text font-size={13} color={MUTED}>1,000,000</text>
				</view>
			</view>
		</view>;
	}
}
