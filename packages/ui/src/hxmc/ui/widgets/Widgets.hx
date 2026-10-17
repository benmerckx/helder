package hxmc.ui.widgets;

import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.reactive.Signal;
import hxmc.ui.reactive.Motion;

// Components for markup (import hxmc.ui.widgets.Widgets.*): built with
// hxmc.ui.reactive, styled plainly (props override the look); their
// colours and the switch's knob move with Motion's transitions
class Widgets implements Markup {
	// a button: label or children; a primary one is filled
	public static function Button(props:{?label:String, ?onClick:Void->Void, ?primary:Bool, ?children:Esx, ?tag:String}):Esx {
		var hover = signal(false), down = signal(false);
		var primary = props.primary == true;
		var bg = () -> primary ? (down.value ? "#1d4ed8" : hover.value ? "#2563eb" : "#3b82f6") : (down.value ? "#d4d4d8" : hover.value ? "#e4e4e7" : "#ffffff");
		return <view tag={props.tag ?? "button"} focusable cursor="pointer" padding="6 14" radius={6} border-width={primary ? 0 : 1} border-color="#a1a1aa" background={Motion.color(bg)}
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
			<view width={16} height={16} radius={4} border-width={1.5} border-color={Motion.color(() -> props.checked.value ? "#2563eb" : "#71717a")}
				background={Motion.color(() -> props.checked.value ? "#3b82f6" : "#ffffff")} align-items="center" justify="center">
				<view width={8} height={8} radius={2} background={Motion.color(() -> props.checked.value ? "#ffffff" : "#ffffff00")}/>
			</view>
			{props.label}
		</view>;
	}

	// a switch bound to a signal, with its label
	public static function Switch(props:{on:Signal<Bool>, ?label:String, ?tag:String}):Esx {
		var toggle = () -> props.on.value = !props.on.value;
		return <view tag={props.tag ?? "switch"} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE || e.key == Key.ENTER) toggle()}>
			<view width={36} height={20} radius={10} padding={2} direction="row"
				background={Motion.color(() -> props.on.value ? "#3b82f6" : "#d4d4d8")}>
				<view width={16} height={16} radius={8} background="#ffffff" shadow="0 1 2 #00000040"
					position="relative" left={Motion.transition(() -> props.on.value ? 16 : 0)}/>
			</view>
			{props.label}
		</view>;
	}

	// a slider bound to a signal: from min to max (0 to 1), in steps (0: any
	// value), width pixels wide (160); dragged, clicked, or moved with the
	// arrow keys (a step, or a twentieth), Home and End
	public static function Slider(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?tag:String}):Esx {
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0, w = props.width ?? 160.0;
		var knob = 16.0;
		function set(v:Float) {
			if (step > 0) v = lo + Math.round((v - lo) / step) * step;
			props.value.value = Math.max(lo, Math.min(hi, v));
		}
		var frac = () -> hi > lo ? (props.value.value - lo) / (hi - lo) : 0.0;
		function at(e:Event) {
			var n = e.current;
			set(lo + (n.localX(e.x) - knob / 2) / (w - knob) * (hi - lo));
		}
		var keyStep = step > 0 ? step : (hi - lo) / 20;
		return <view tag={props.tag ?? "slider"} width={w} height={knob + 4} focusable cursor="pointer" justify="center"
			onPointerDown={e -> at(e)} onPointerMove={e -> if (e.current.pressed) at(e)}
			onKeyDown={e -> switch e.key {
				case Key.LEFT | Key.DOWN: set(props.value.value - keyStep);
				case Key.RIGHT | Key.UP: set(props.value.value + keyStep);
				case Key.HOME: set(lo);
				case Key.END: set(hi);
				case _:
			}}>
			<view height={4} radius={2} margin={[0, knob / 2]} overflow="hidden" direction="row" background="#d4d4d8">
				<view width={() -> (frac() * 100) + "%"} background="#3b82f6"/>
			</view>
			<view position="absolute" top={2} left={() -> frac() * (w - knob)} width={knob} height={knob} radius={knob / 2} background="#ffffff"
				border-width={1} border-color="#a1a1aa" shadow="0 1 2 #00000033"/>
		</view>;
	}

	// radio buttons bound to a signal: one per option (tag: the group's tag,
	// "-", the option)
	public static function Radio(props:{value:Signal<String>, options:Array<String>, ?tag:String}):Esx {
		var tag = props.tag ?? "radio";
		return <view tag={tag} row-gap={6}>{[
			for (o in props.options)
				<view tag={tag + "-" + o} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> props.value.value = o}
					onKeyDown={e -> if (e.key == Key.SPACE) props.value.value = o}>
					<view width={16} height={16} radius={8} border-width={1.5} border-color={Motion.color(() -> props.value.value == o ? "#2563eb" : "#71717a")}
						align-items="center" justify="center">
						<view width={8} height={8} radius={4} background={Motion.color(() -> props.value.value == o ? "#3b82f6" : "#3b82f600")}/>
					</view>
					{o}
				</view>
		]}</view>;
	}

	// tabs: a row of labels (tag: the tabs' tag, "-", the index), the
	// selected one underlined, and what render gives for it below
	public static function Tabs(props:{labels:Array<String>, selected:Signal<Int>, render:Int->Any, ?tag:String}):Esx {
		var tag = props.tag ?? "tabs";
		return <view tag={tag} row-gap={10}>
			<view direction="row" column-gap={4}>{[
				for (i in 0...props.labels.length)
					<view tag={tag + "-" + i} focusable cursor="pointer" padding="6 10 0 10" row-gap={6} align-items="center"
						onClick={_ -> props.selected.value = i} onKeyDown={e -> if (e.key == Key.SPACE || e.key == Key.ENTER) props.selected.value = i}
						color={Motion.color(() -> props.selected.value == i ? "#1d4ed8" : "#52525b")}>
						{props.labels[i]}
						<view align-self="stretch" height={2} radius={1} background={Motion.color(() -> props.selected.value == i ? "#3b82f6" : "#3b82f600")}/>
					</view>
			]}</view>
			{() -> props.render(props.selected.value)}
		</view>;
	}

	// a progress bar: value from 0 to 1 (a signal, a function or a number)
	public static function Progress(props:{value:Dynamic, ?width:Float, ?tag:String}):Esx {
		var frac = () -> {
			var v:Float = Render.read(props.value);
			v < 0 ? 0.0 : v > 1 ? 1.0 : v;
		};
		return <view tag={props.tag ?? "progress"} width={props.width ?? 160} height={8} radius={4} overflow="hidden" direction="row" background="#e4e4e7">
			<view width={() -> (frac() * 100) + "%"} background="#3b82f6"/>
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
