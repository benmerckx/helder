package helder.ui.widgets;

import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Svg;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// Small controls with their look by slot (Theme's): a slider and a
// segmented choice.
//
//   <Slider label="Weight" value={weight} min={20} max={200} step={1} onChange={weight}/>
//   <Segmented label="Tool" value={tool} options={[{value: "draw", label: "Draw"}, ...]} onChange={tool}/>
class Controls implements Markup {
	// A number between min and max, shown as a field (its label inside on
	// the left, its value on the right, the part up to it filled): a press
	// or a drag anywhere sets it, the arrow keys step it (Shift: ten steps),
	// Home and End go to the ends. step 0: any value. Slots: "slider",
	// "slider-fill", "field-label", "slider-value".
	public static function Slider(props:{label:String, value:Read<Float>, min:Float, max:Float, ?step:Float, ?digits:Int, ?unit:String,
		onChange:Float->Void, ?tag:String}):View {
		var step = props.step ?? 0.0, range = props.max - props.min;
		var digits = props.digits ?? (step >= 1 || step == 0 && range >= 20 ? 0 : step >= 0.1 ? 1 : 2);
		var root:Null<Node> = null, dragging = false;
		function fraction():Float {
			var f = range == 0 ? 0 : (props.value() - props.min) / range;
			return f < 0 ? 0 : f > 1 ? 1 : f;
		}
		function set(v:Float) {
			if (step > 0) v = props.min + Math.round((v - props.min) / step) * step;
			if (v < props.min) v = props.min;
			if (v > props.max) v = props.max;
			props.onChange(v);
		}
		function at(x:Float) {
			var r = root;
			if (r == null || r.width <= 0) return;
			set(props.min + (x - r.absX) / r.width * range);
		}
		function by(n:Float)
			set(props.value() + n * (step > 0 ? step : range / 100));
		return <view tag={props.tag} slot="slider" role="slider" label={props.label} focusable value-now={props.value()} value-min={props.min}
			value-max={props.max} ref={(n:Node) -> root = n} onPointerDown={e -> {
				root?.capture();
				dragging = true;
				at(e.x);
			}} onPointerMove={e -> if (dragging) at(e.x)} onPointerUp={_ -> dragging = false} onLostPointerCapture={_ -> dragging = false}
			onKeyDown={e -> {
				var shift = e.mods & Key.MOD_SHIFT != 0 ? 10 : 1;
				if (e.key == Key.RIGHT || e.key == Key.UP) by(shift) else if (e.key == Key.LEFT || e.key == Key.DOWN) by(-shift) else if (e.key == Key.HOME)
					set(props.min) else if (e.key == Key.END) set(props.max) else return;
				e.preventDefault();
			}}>
			<view slot="slider-fill" position="absolute" left={0} top={0} bottom={0} width={(fraction() * 100) + "%"} pointer-events="none"/>
			<text slot="field-label" grow={1} pointer-events="none">{props.label}</text>
			<text slot="slider-value" pointer-events="none" font-variant-numeric="tabular-nums">{format(props.value(), digits) + (props.unit ?? "")}</text>
		</view>;
	}

	// One of a few options side by side, the chosen one marked (data-on):
	// a press chooses, the arrow keys move between them. Slots: "seg",
	// "seg-item" (an icon follows its colour).
	public static function Segmented(props:{label:String, value:Read<String>, options:Array<{value:String, label:String, ?icon:Svg, ?hint:String}>,
		onChange:String->Void, ?tag:String, ?compact:Bool}):View {
		function move(by:Int) {
			var i = 0;
			for (k in 0...props.options.length)
				if (props.options[k].value == props.value()) i = k;
			var n = props.options.length;
			props.onChange(props.options[(i + by + n) % n].value);
		}
		return <view tag={props.tag} slot="seg" role="radiogroup" label={props.label} onKeyDown={e -> {
			if (e.key == Key.RIGHT || e.key == Key.DOWN) move(1) else if (e.key == Key.LEFT || e.key == Key.UP) move(-1) else return;
			e.preventDefault();
		}}>
			<For each={props.options}>{(o:Read<{value:String, label:String, ?icon:Svg, ?hint:String}>) -> {
				var option = o();
				<view:button tag={props.tag == null ? null : props.tag + "-" + option.value} slot="seg-item" role="radio" label={option.hint ?? option.label}
					focusable checked={props.value() == option.value} data-on={props.value() == option.value ? "true" : "false"}
					onPress={() -> props.onChange(option.value)}>
					<Show when={option.icon != null}><image src={option.icon} width={14} height={14} shrink={0}/></Show>
					<Show when={!(props.compact ?? false) || option.icon == null}><text>{option.label}</text></Show>
				</view:button>;
			}}</For>
		</view>;
	}

	static function format(v:Float, digits:Int):String {
		if (digits <= 0) return Std.string(Math.round(v));
		var p = Math.pow(10, digits), s = Std.string(Math.round(Math.abs(v) * p));
		while (s.length <= digits)
			s = "0" + s;
		return (v < 0 && Math.round(Math.abs(v) * p) != 0 ? "-" : "") + s.substr(0, s.length - digits) + "." + s.substr(s.length - digits);
	}
}
