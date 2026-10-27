// title: Tree
// summary: A tree of files, its first folder open, the selected file shown under it
import helder.ui.widgets.Widgets.*;
import helder.view.*;
import helder.view.Reactive.*;

private typedef Entry = {name:String, ?children:Array<Entry>};

class TreeExample implements Markup {
	public static function view():View {
		var files:Array<Entry> = [
			{name: "src", children: [{name: "Main.hx"}, {name: "ui", children: [{name: "Button.hx"}, {name: "Tree.hx"}]}]},
			{name: "test", children: [{name: "TreeTest.hx"}]},
			{name: "README.md"}
		];
		var open = signal([files[0]]);
		var selected:Signal<Null<Entry>> = signal(null);
		return <view row-gap={8} width={260}>
			<Tree tag="files" roots={files} children={(e:Entry) -> e.children} render={(e:Entry) -> e.name} text={(e:Entry) -> e.name}
				expanded={open} selected={selected} height={180} label="Files"/>
			<text>{() -> selected.value == null ? "Nothing selected" : selected.value.name + " selected"}</text>
		</view>;
	}
}
