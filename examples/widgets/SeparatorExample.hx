// title: Separator
// summary: A horizontal separator between blocks, vertical ones between links
import helder.ui.widgets.Widgets.*;
import helder.view.*;

class SeparatorExample implements Markup {
	public static function view():View {
		return <view row-gap={12} width={280}>
			<text>Widgets</text>
			<Separator tag="across"/>
			<view direction="row" column-gap={12} align-items="center" height={20}>
				<text>Blog</text>
				<Separator tag="down" orientation="vertical"/>
				<text>Docs</text>
				<Separator orientation="vertical" decorative={false}/>
				<text>Source</text>
			</view>
		</view>;
	}
}
