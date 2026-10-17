import hxmc.ui.widgets.Toasts;
import hxmc.view.*;
import hxmc.web.widgets.Widgets.*;
import hxmc.web.widgets.Widgets.MenuItem;
import js.Browser.document;

// The bundle dom-fidelity.mjs drives (make theme-dom-check): renderCase(c,
// width, height) renders a case of ref/cases.json with the DOM's widgets
// in #frame as ref.mjs frames shadcn's markup (false: no widget for it);
// toast(text, action) shows a toast.
class DomFidelity implements Markup {
	static var dispose:Null<Void->Void>;

	static final MENU:Array<MenuItem> = [
		{label: "Profile", shortcut: "Mod+P", onSelect: () -> {}},
		{label: "Billing", shortcut: "Mod+B", onSelect: () -> {}},
		{label: "", separator: true},
		{label: "Delete", variant: "destructive", onSelect: () -> {}},
		{label: "Disabled", disabled: true}
	];

	// (null: no widget for the component yet)
	static function widget(c:Dynamic):Null<View> {
		var text:String = c.text, variant:String = c.variant ?? "default", size:String = c.size ?? "default";
		return switch (c.component : String) {
			case "button": <Button label={text} variant={variant} size={size}/>;
			case "badge": <Badge label={text} variant={variant}/>;
			case "toggle": <Toggle pressed={new Signal(c.on == true)} label={text} variant={variant} size={size}/>;
			case "input": <Input value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "textarea": <Textarea value={new Signal(text ?? "")} placeholder={c.placeholder}/>;
			case "checkbox": <Checkbox checked={new Signal(c.checked == true)}/>;
			case "switch": <Switch checked={new Signal(c.checked == true)} size={size}/>;
			case "label" if (c.peerDisabled == true): <Checkbox checked={new Signal(false)} label={text} disabled={true}/>;
			case "label": <Label text={text}/>;
			case "card":
				<Card>
					<CardHeader>
						<CardTitle text={c.title}/>
						<CardDescription text={c.description}/>
						<CardAction><Button variant="link" label={c.action}/></CardAction>
					</CardHeader>
					<CardContent><p>{text}</p></CardContent>
					<CardFooter><Button label={c.footer}/></CardFooter>
				</Card>;
			case "separator":
				<div>
					<div style="font-size:14px;line-height:1;font-weight:500">Radix Primitives</div>
					<div style="margin:16px 0"><Separator/></div>
					<div style="font-size:14px;line-height:20px">Blog</div>
				</div>;
			case "skeleton":
				<div style="display:flex;align-items:center;gap:16px">
					<div style="border-radius:9999px;overflow:hidden"><Skeleton width={48} height={48}/></div>
					<div style="display:flex;flex-direction:column;gap:8px"><Skeleton width={200} height={16}/><Skeleton width={150} height={16}/></div>
				</div>;
			case "alert": <Alert variant={variant}><AlertTitle text={c.title}/><AlertDescription text={text}/></Alert>;
			case "avatar": <Avatar fallback="CN"/>;
			case "radio-group": <RadioGroup value={new Signal("Default")} options={["Default", "Comfortable"]}/>;
			case "slider": <Slider value={new Signal((c.value : Float) / 100)}/>;
			case "tabs": <Tabs labels={["Account", "Password"]} selected={new Signal(0)} variant={c.variant} render={_ -> "Make changes to your account here."}/>;
			case "progress": <Progress value={(c.value : Float) / 100}/>;
			case "toggle-group": <ToggleGroup value={new Signal("Italic")} options={["Bold", "Italic", "Underline"]} variant={variant}/>;
			case "accordion":
				<Accordion open={new Signal(0)} sections={[
					{label: "Product Information", render: () -> "Our flagship product combines cutting-edge technology with sleek design."},
					{label: "Shipping Details", render: () -> "We offer worldwide shipping."}
				]}/>;
			case "breadcrumb": <Breadcrumb items={["Home", "Components", "Breadcrumb"]} onSelect={_ -> {}}/>;
			case "pagination": <Pagination page={new Signal(2)} count={10}/>;
			case "kbd": <Kbd text="Ctrl"/>;
			case "spinner": <Spinner/>;
			case _: null;
		}
	}

	static function renderCase(c:Dynamic, w:Int, h:Int):Bool {
		if (dispose != null) dispose();
		dispose = null;
		Toasts.clear();
		var html = document.documentElement;
		html.className = c.dark == true ? "dark" : "";
		if (c.rtl == true) html.setAttribute("dir", "rtl") else html.removeAttribute("dir");
		var frame = document.getElementById("frame");
		frame.setAttribute("style", 'box-sizing:border-box;width:${w}px;height:${h}px;padding:16px;background-color:var(--background)'
			+ (c.block == true ? "" : ";display:flex;align-items:flex-start"));
		var v = widget(c);
		if (v == null) return false;
		dispose = Render.render(v, frame);
		return true;
	}

	static function main() {
		js.Syntax.code("window.renderCase = {0}", renderCase);
		js.Syntax.code("window.toast = {0}", (text:String, action:String) -> Toasts.show(text, {action: action, duration: 0}));
	}
}
