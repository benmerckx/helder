// title: Sign-up card
// summary: A card of plain views styled by a StyleSheet of its own: a field, a checkbox, a switch, a badge and buttons, light and dark
// tags: ui, styles
// demo: canvas 420x360
import helder.ui.*;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// A card of controls made of views (each with its role, focusable, pressed
// by a click, Enter or Space), their look Signup.sheet's rules: by slot,
// state (hover, focus, data-state, data-disabled) and dark mode, its
// colours tokens with a light and a dark value. The switch turns dark
// mode on (the window's Ui.dark).
class Signup implements Markup {
	static function main() {
		var dark = signal(false);
		UiWindow.run(<Surface title="Sign up" width={420} height={360} theme={sheet} dark={dark}>{view(dark)}</Surface>);
	}

	public static function view(dark:Signal<Bool>):View {
		var email = signal(""), terms = signal(false);
		return <view slot="body" grow={1} padding={24} font-size={14}>
			<view slot="card">
				<view direction="row" align-items="start">
					<view grow={1} row-gap={4}>
						<text font-size={16} font-weight={600}>Create an account</text>
						<text slot="muted">Enter your email below</text>
					</view>
					<text slot="badge" font-size={12}>Beta</text>
				</view>
				<view row-gap={12}>
					<field slot="input" value={email} placeholder="m@example.com" label="Email" onInput={e -> email(e.text)}/>
					<Checkbox checked={terms} label="Accept terms"/>
					<Switch checked={dark} label="Dark mode"/>
				</view>
				<view direction="row" column-gap={8}>
					<Button variant="outline" label="Cancel"/>
					<Button label="Sign up" disabled={() -> !terms()}/>
				</view>
			</view>
		</view>;
	}

	static inline function token(name:String):Color
		return Color.parse('var(--$name)');

	public static final sheet:StyleSheet = {
		rules: [
			{slot: "body", style: {background: token("background"), color: token("foreground")}},
			{slot: "card", style: {rowGap: 24, padding: 24, radius: 12, borderWidth: 1, borderColor: token("border"), background: token("card")}},
			{slot: "muted", style: {color: token("muted")}},
			{slot: "badge", style: {padding: [2, 8], radius: 6, background: token("secondary"), fontWeight: 500}},
			{slot: "input", style: {padding: [6, 12], radius: 6, borderWidth: 1, borderColor: token("input")}},
			{slot: "input", when: ["focus"], style: {borderColor: token("muted")}},
			{slot: "input", when: ["placeholder"], style: {color: token("muted")}},
			{slot: "button", style: {padding: [8, 16], radius: 6, background: token("primary"), color: token("primary-foreground"), fontWeight: 500, cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {background: Color.parse("var(--primary)/90")}},
			{slot: "button", variant: "outline", style: {background: Color.TRANSPARENT, color: token("foreground"), borderWidth: 1, borderColor: token("border")}},
			{slot: "button", variant: "outline", when: ["hover"], style: {background: token("secondary")}},
			{slot: "button", when: ["data-disabled"], style: {opacity: 0.5, cursor: Default}},
			{slot: "checkbox", style: {width: 16, height: 16, radius: 4, borderWidth: 1, borderColor: token("input"), alignItems: Center, justify: Center,
				cursor: Pointer}},
			{slot: "checkbox", when: ["data-state=checked"], style: {background: token("primary"), borderColor: token("primary"), color: token("primary-foreground")}},
			{slot: "switch", style: {width: 32, height: 18, radius: 9, padding: 2, background: token("input"), direction: Row, alignItems: Center, cursor: Pointer}},
			{slot: "switch", when: ["data-state=checked"], style: {background: token("primary"), justify: End}},
			{slot: "switch-thumb", style: {width: 14, height: 14, radius: 7, background: token("background")}},
			{slot: "switch-thumb", when: ["data-state=checked"], style: {background: token("primary-foreground")}}
		],
		light: [
			"background" => Color.rgb(0xFFFFFF), "foreground" => Color.rgb(0x0A0A0A), "card" => Color.rgb(0xFFFFFF), "border" => Color.rgb(0xE5E5E5),
			"input" => Color.rgb(0xE5E5E5), "muted" => Color.rgb(0x737373), "primary" => Color.rgb(0x171717), "primary-foreground" => Color.rgb(0xFAFAFA),
			"secondary" => Color.rgb(0xF5F5F5)
		],
		dark: [
			"background" => Color.rgb(0x0A0A0A), "foreground" => Color.rgb(0xFAFAFA), "card" => Color.rgb(0x171717), "border" => Color.rgba(0xFFFFFF, 0.1),
			"input" => Color.rgba(0xFFFFFF, 0.15), "muted" => Color.rgb(0xA1A1A1), "primary" => Color.rgb(0xE5E5E5), "primary-foreground" => Color.rgb(0x171717),
			"secondary" => Color.rgb(0x262626)
		]
	};

	static function Button(props:{label:String, ?variant:String, ?disabled:Void->Bool, ?onClick:Void->Void}):View {
		var off = () -> props.disabled != null && props.disabled();
		return <view:button slot="button" variant={props.variant} role="button" focusable={() -> !off()} disabled={off} data-disabled={off}
			onPress={_ -> if (!off() && props.onClick != null) props.onClick()}>{props.label}</view:button>;
	}

	// (a box and its label in a row: either pressed toggles it; the box named by the label)
	static function Checkbox(props:{checked:Signal<Bool>, label:String}):View {
		var toggle = () -> props.checked(c -> !c);
		var state = () -> props.checked() ? "checked" : "unchecked";
		return <view direction="row" align-items="center" column-gap={8}>
			<view:button slot="checkbox" role="checkbox" label={props.label} checked={props.checked} data-state={state} focusable onPress={_ -> toggle()}>
				<Show when={props.checked}><icon name="check" width={12} height={12}/></Show>
			</view:button>
			<text hidden cursor="pointer" onClick={_ -> toggle()}>{props.label}</text>
		</view>;
	}

	// (a track and its thumb, at the end while it is on)
	static function Switch(props:{checked:Signal<Bool>, label:String}):View {
		var toggle = () -> props.checked(c -> !c);
		var state = () -> props.checked() ? "checked" : "unchecked";
		return <view direction="row" align-items="center" column-gap={8}>
			<view:button slot="switch" role="switch" label={props.label} checked={props.checked} data-state={state} focusable onPress={_ -> toggle()}>
				<view slot="switch-thumb" data-state={state}/>
			</view:button>
			<text hidden cursor="pointer" onClick={_ -> toggle()}>{props.label}</text>
		</view>;
	}
}
