import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import Plain.*;

// The controls every accessibility adapter's test reads (MarkupTest's
// accessFixture headless; LinuxAccessTest, WinAccessTest, MacAccessTest,
// the phones' and the browser's in their windows): a label, a button, a
// checkbox, a slider, a field and a read-only one, a text area, a
// disclosure (expanded or not), a list of three items, a table (a header
// row and two rows of cells, the rows selectable), tabs, a live region and
// a scroll view whose last item starts out of sight. The state the actions
// change is in its fields.
class AccessFixture implements Markup {
	public var saved = 0;
	public final checked = signal(false);
	public final volume = signal(0.5);
	public final name = signal("Ada");
	public final notes = signal("one\ntwo");
	public final open = signal(false);
	public final row = signal(0);
	public final tab = signal(0);
	public final status = signal("Ready");

	public function new() {}

	public function view():View
		return <view tag="fixture" padding={8} row-gap={4} align-items="start">
			<text>Settings</text>
			<Button tag="save" label="Save" onClick={() -> saved++}/>
			<Checkbox tag="remember" checked={checked} label="Remember"/>
			<Slider tag="volume" value={volume} step={0.1} label="Volume"/>
			<field tag="name" value={name} placeholder="Name" label="Name" onInput={e -> name(e.text)} width={120}/>
			<field tag="code" value={"X1"} readonly label="Code" width={60}/>
			<field:textarea tag="notes" value={notes} label="Notes" onInput={e -> notes(e.text)} width={120}/>
			<view:button tag="more" role="button" expanded={open} focusable onPress={() -> open(o -> !o)}>More</view:button>
			<Show when={open}><text tag="extra">Extra</text></Show>
			<view tag="fruits" role="list" label="Fruits" direction="row" column-gap={6}>
				<view role="listitem">Apple</view><view role="listitem">Pear</view><view role="listitem">Plum</view>
			</view>
			<view tag="table" role="grid" label="Mail">
				<view role="row" direction="row" column-gap={6}><view role="columnheader">From</view><view role="columnheader">Subject</view></view>
				<Repeat count={2}>{i -> <view tag={"row" + i} role="row" direction="row" column-gap={6} focusable selected={() -> row() == i}
					onClick={_ -> row(i)}>
					<view role="cell">{["Ann", "Bob"][i]}</view><view role="cell">{["Hello", "Lunch"][i]}</view>
				</view>}</Repeat>
			</view>
			<view tag="tabs" role="tablist" direction="row" column-gap={6}>
				<Repeat count={2}>{i -> <view:button role="tab" focusable selected={() -> tab() == i} onPress={() -> tab(i)}>{["General", "Advanced"][i]}</view:button>}</Repeat>
			</view>
			<view tag="status" live="polite"><text>{status}</text></view>
			<view tag="scroller" overflow="scroll" height={20} width={80}>
				<text>First</text><text>Second</text><text tag="last">Last</text>
			</view>
		</view>;
}
