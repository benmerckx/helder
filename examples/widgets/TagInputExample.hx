// title: TagInput
// summary: Tags typed into one box, added with Enter or a comma, the list shown under it
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

class TagInputExample implements Markup {
	public static function view():View {
		var tags = signal(["red", "green"]);
		return <view row-gap={8} width={320}>
			<TagInput tag="colours" tags={tags} placeholder="Add a colour" label="Colours"/>
			<text>{() -> tags.value.length + " tags: " + tags.value.join(", ")}</text>
		</view>;
	}
}
