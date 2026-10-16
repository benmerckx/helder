package hxmc.ui.widgets;

import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.reactive.Signal;

// Components for markup (import hxmc.ui.widgets.Widgets.*): built with
// hxmc.ui.reactive, styled plainly (props override the look)
class Widgets implements Markup {
	// a button: label or children; a primary one is filled
	public static function Button(props:{?label:String, ?onClick:Void->Void, ?primary:Bool, ?children:Esx, ?tag:String}):Esx {
		var hover = signal(false), down = signal(false);
		var primary = props.primary == true;
		var bg = () -> primary ? (down.value ? "#1d4ed8" : hover.value ? "#2563eb" : "#3b82f6") : (down.value ? "#d4d4d8" : hover.value ? "#e4e4e7" : "#ffffff");
		return <view tag={props.tag ?? "button"} focusable cursor="pointer" padding="6 14" radius={6} border-width={primary ? 0 : 1} border-color="#a1a1aa" background={bg}
			color={primary ? "#ffffff" : "#18181b"} align-items="center" onPointerEnter={_ -> hover.value = true}
			onPointerLeave={_ -> {
				hover.value = false;
				down.value = false;
			}} onPointerDown={_ -> down.value = true} onPointerUp={_ -> down.value = false}
			onClick={_ -> if (props.onClick != null) props.onClick()}
			onKeyDown={e -> if ((e.key == Key.ENTER || e.key == Key.SPACE) && props.onClick != null) props.onClick()}>
			{props.label}{props.children}
		</view>;
	}

	// a checkbox bound to a signal, with its label
	public static function Checkbox(props:{checked:Signal<Bool>, ?label:String, ?tag:String}):Esx {
		var toggle = () -> props.checked.value = !props.checked.value;
		return <view tag={props.tag ?? "checkbox"} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE) toggle()}>
			<view width={16} height={16} radius={4} border-width={1.5} border-color={() -> props.checked.value ? "#2563eb" : "#71717a"}
				background={() -> props.checked.value ? "#3b82f6" : "#ffffff"} align-items="center" justify="center">
				<view width={8} height={8} radius={2} background={() -> props.checked.value ? "#ffffff" : "#00000000"}/>
			</view>
			{props.label}
		</view>;
	}

	// a text field bound to a signal (two ways)
	public static function Field(props:{value:Signal<String>, ?placeholder:String, ?onSubmit:String->Void, ?tag:String}):Node {
		var f = new TextField(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.placeholder = props.placeholder ?? "";
		f.style.set({padding: [6, 8], borderWidth: 1, borderColor: Color.rgb(0xA1A1AA), radius: 6, background: Color.WHITE});
		f.onChange = s -> props.value.value = s;
		f.onSubmit = props.onSubmit;
		effect(() -> f.setText(props.value.value));
		return f;
	}
}
