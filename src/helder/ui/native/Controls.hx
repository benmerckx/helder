package helder.ui.native;

import helder.ui.*;
import helder.view.*;
import helder.view.Reactive.*;

// Platform controls as markup components (import helder.ui.native.Controls.*),
// in a NativeHost: bound to signals both ways, as the drawn widgets are.
// Values may be signals, memos or functions (bound) or plain; style takes
// the control's layout properties.
class Controls {
	static function bind(v:Dynamic, set:Dynamic->Void)
		if (Render.isReactive(v)) effect(() -> set(Render.read(v))) else if (v != null) set(v);

	static function control(kind:ControlKind, tag:Null<String>, style:Null<StyleProps>):Control {
		var c = new Control(kind, tag);
		if (style != null) c.style.set(style);
		return c;
	}

	public static function Button(props:{label:Dynamic, ?onClick:Void->Void, ?enabled:Dynamic, ?style:StyleProps, ?tag:String}):Node {
		var c = control(ControlKind.Button, props.tag ?? "button", props.style);
		bind(props.label, v -> c.text = Std.string(v));
		bind(props.enabled, v -> c.enabled = v);
		c.onPress = props.onClick;
		return c;
	}

	public static function Checkbox(props:{checked:Signal<Bool>, label:Dynamic, ?style:StyleProps, ?tag:String}):Node {
		var c = control(ControlKind.CheckBox, props.tag ?? "checkbox", props.style);
		bind(props.label, v -> c.text = Std.string(v));
		bind(props.checked, v -> c.checked = v);
		c.onToggle = b -> props.checked.value = b;
		return c;
	}

	public static function Field(props:{value:Signal<String>, ?placeholder:String, ?onSubmit:String->Void, ?style:StyleProps, ?tag:String}):Node {
		var c = control(ControlKind.TextField, props.tag ?? "field", props.style);
		if (props.placeholder != null) c.placeholder = props.placeholder;
		bind(props.value, v -> c.text = v);
		c.onText = t -> props.value.value = t;
		c.onSubmit = props.onSubmit;
		return c;
	}

	public static function Slider(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?style:StyleProps, ?tag:String}):Node {
		var c = control(ControlKind.Slider, props.tag ?? "slider", props.style);
		c.min = props.min ?? 0.0;
		c.max = props.max ?? 1.0;
		c.step = props.step ?? 0.0;
		bind(props.value, v -> c.value = v);
		c.onValue = v -> props.value.value = v;
		return c;
	}

	public static function Progress(props:{value:Dynamic, ?style:StyleProps, ?tag:String}):Node {
		var c = control(ControlKind.Progress, props.tag ?? "progress", props.style);
		bind(props.value, v -> c.value = v);
		return c;
	}
}
