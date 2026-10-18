package hxmc.web;

#if js
import js.html.Element;

// A page's element as a widget's part (hxmc.ui.Part): what a neutral
// element's ref gets in the DOM's renderer, made only then. Its methods
// kept whenever one is made (ifFeature): neutral widgets call a Part's
// opaquely in a page (through the interface they would keep a Node's too)
class ElementPart implements hxmc.ui.Part {
	public final element:Element;

	function new(element:Element)
		this.element = element;

	public static function of(el:Dynamic):ElementPart
		return new ElementPart(el);

	@:ifFeature("hxmc.web.ElementPart.of") public function focus(visible:Bool = true)
		(cast element : Dynamic).focus({focusVisible: visible});

	@:ifFeature("hxmc.web.ElementPart.of") public function rect():{x:Float, y:Float, width:Float, height:Float} {
		var r = element.getBoundingClientRect();
		return {x: r.left, y: r.top, width: r.width, height: r.height};
	}

	@:ifFeature("hxmc.web.ElementPart.of") public function scrollIntoView()
		(cast element : Dynamic).scrollIntoView({block: "nearest", "inline": "nearest"});

	@:ifFeature("hxmc.web.ElementPart.of") public function contains(p:hxmc.ui.Part):Bool {
		var o = Std.downcast(p, ElementPart);
		return o != null && element.contains(o.element);
	}

	@:ifFeature("hxmc.web.ElementPart.of") public function attr(name:String):Null<String>
		return element.getAttribute(name);

	// (the pointer last pressed in a neutral element's handler: Neutral.call's)
	@:ifFeature("hxmc.web.ElementPart.of") public function capture()
		if (Neutral.pointer != null) element.setPointerCapture(Neutral.pointer);

	// (a field's selection: an <input>'s or a <textarea>'s)
	@:ifFeature("hxmc.web.ElementPart.of") public function select(start:Int, end:Int)
		if ((cast element : Dynamic).setSelectionRange != null) (cast element : Dynamic).setSelectionRange(start, end);

	@:ifFeature("hxmc.web.ElementPart.of") public function rtl():Bool
		return js.Browser.window.getComputedStyle(element).direction == "rtl";

	// (the outermost of the elements the keys reach, those with a tabindex too: a roving one out of the tab order)
	@:ifFeature("hxmc.web.ElementPart.of") public function focusables():Array<hxmc.ui.Part> {
		var all = [for (n in element.querySelectorAll("button,input,select,textarea,a[href],[tabindex]")) (cast n : Element)];
		return [for (e in all) if (!Lambda.exists(all, o -> o != e && o.contains(e))) (new ElementPart(e) : hxmc.ui.Part)];
	}

	@:ifFeature("hxmc.web.ElementPart.of") public function tabStop(on:Bool)
		element.setAttribute("tabindex", on ? "0" : "-1");

	@:ifFeature("hxmc.web.ElementPart.of") public function holdsFocus():Bool {
		var a = js.Browser.document.activeElement;
		return a != null && element.contains(a);
	}

	@:ifFeature("hxmc.web.ElementPart.of") public function editable():Bool
		return element.localName == "input" || element.localName == "textarea" || element.isContentEditable;
}
#end
