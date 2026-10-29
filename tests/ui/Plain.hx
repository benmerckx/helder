import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Signal;

// Plain controls for the tests (import Plain.*): views with a role, a
// name and their state for assistive technology, focusable, pressed by a
// click, Enter or Space (view:button's onPress), no look but a line in the
// text's colour where a box needs one. A button, a checkbox (its label
// beside it pressing it too), a slider from 0 to 1 (Left and Down a step
// less, Right and Up more: what assistive technology's Increment and
// Decrement press).
class Plain implements Markup {
	public static function Button(props:{label:String, ?onClick:Void->Void, ?tag:String}):View
		return <view:button tag={props.tag ?? "button"} role="button" focusable padding="2 8" border-width={1} border-color="currentColor"
			onPress={() -> if (props.onClick != null) props.onClick()}>{props.label}</view:button>;

	public static function Checkbox(props:{checked:Signal<Bool>, ?label:String, ?tag:String}):View {
		var toggle = () -> props.checked(c -> !c);
		var box = <view:button tag={props.tag ?? "checkbox"} role="checkbox" label={props.label} checked={props.checked} width={14} height={14}
			border-width={1} border-color="currentColor" align-items="center" justify="center" focusable onPress={() -> toggle()}>
			<Show when={props.checked}><view width={8} height={8} background="currentColor"/></Show>
		</view:button>;
		return props.label == null ? box : <view direction="row" align-items="center" column-gap={6}>
			{box}<text hidden onClick={_ -> toggle()}>{props.label}</text>
		</view>;
	}

	public static function Slider(props:{value:Signal<Float>, ?step:Float, ?label:String, ?tag:String, ?width:Float}):View {
		var step = props.step ?? 0.1, width = props.width ?? 100;
		var to = (v:Float) -> props.value(Math.max(0, Math.min(1, Math.fround(v / step) * step)));
		return <view tag={props.tag ?? "slider"} role="slider" label={props.label} value-now={props.value} value-min={0} value-max={1} focusable
			width={width} height={12} border-width={1} border-color="currentColor" onKeyDown={e -> switch e.key {
				case Key.RIGHT | Key.UP:
					to(props.value.peek() + step);
					e.preventDefault();
				case Key.LEFT | Key.DOWN:
					to(props.value.peek() - step);
					e.preventDefault();
				case _:
			}}>
			<view height="100%" width={props.value() * (width - 2)} background="currentColor"/>
		</view>;
	}
}
