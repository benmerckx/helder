// title: Kbd
// summary: Keys as typed, alone and in a sentence
import helder.ui.widgets.Widgets.*;
import helder.view.*;

class KbdExample implements Markup {
	public static function view():View {
		return <view row-gap={12}>
			<view direction="row" column-gap={4} align-items="center">
				<Kbd tag="ctrl" text="Ctrl"/>
				<Kbd tag="shift" text="Shift"/>
				<Kbd tag="k" text="K"/>
			</view>
			<view direction="row" column-gap={6} align-items="center">
				<text>Press</text>
				<Kbd tag="save" text="Ctrl S"/>
				<text>to save.</text>
			</view>
		</view>;
	}
}
