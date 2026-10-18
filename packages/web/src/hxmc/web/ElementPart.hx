package hxmc.web;

#if js
import js.html.Element;

// A page's element as a widget's part (hxmc.ui.Part): what a neutral
// element's ref gets in the DOM's renderer, made only then, and an event's
// current. Kept whole: neutral widgets call a Part's methods opaquely in a
// page (through the interface they would keep a Node's too)
@:keep class ElementPart implements hxmc.ui.Part {
	public final element:Element;

	function new(element:Element)
		this.element = element;

	public static function of(el:Dynamic):ElementPart
		return new ElementPart(el);

	public function focus(visible:Bool = true)
		(cast element : Dynamic).focus({focusVisible: visible});

	public function rect():{x:Float, y:Float, width:Float, height:Float} {
		var r = element.getBoundingClientRect();
		return {x: r.left, y: r.top, width: r.width, height: r.height};
	}

	public function scrollIntoView()
		(cast element : Dynamic).scrollIntoView({block: "nearest", "inline": "nearest"});

	public function contains(p:hxmc.ui.Part):Bool {
		var o = Std.downcast(p, ElementPart);
		return o != null && element.contains(o.element);
	}

	public function attr(name:String):Null<String>
		return element.getAttribute(name);

	public function rtl():Bool
		return js.Browser.window.getComputedStyle(element).direction == "rtl";
}
#end
