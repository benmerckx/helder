// title: Carousel
// summary: Five slides moved through by Previous and Next or the arrow keys, the index shown
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class CarouselExample implements Markup {
	public static function view():View {
		var index = signal(0);
		return <view width={280} row-gap={8} align-items="center">
			<Carousel tag="carousel" index={index} slides={[
				for (i in 0...5)
					<view height={120} align-items="center" justify="center" border-width={1} border-color="#e4e4e7" radius={8}>
						<text font-size={32} font-weight={600}>{Std.string(i + 1)}</text>
					</view>
			]}/>
			<text>{() -> "Slide " + (index.value + 1) + " of 5"}</text>
		</view>;
	}
}
