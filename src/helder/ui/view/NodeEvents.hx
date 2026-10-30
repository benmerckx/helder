package helder.ui.view;

import helder.ui.Event;
import helder.ui.gesture.Pan;
import helder.ui.gesture.Scale;
import helder.ui.gesture.Tap;

// ui's events, by attribute (NodeRenderer's @:events): what each handler is
// given, and the neutral elements' (view, text, view:button...) in every
// renderer, a page's renderer realising them as its own. Markup checks a
// handler against it: a function of this type or of none (onPress={() -> ...}),
// an untyped parameter typed by it (onInput={e -> name(e.text)}); a name
// not here is no event. Data, not code: helder.typescript's manifest and
// declarations read it as they read the elements.
typedef NodeEvents = {
	// a click, or Enter or Space on a focused node (Node.onActivate)
	onPress:Event,
	onClick:Event,
	onPointerDown:Event,
	onPointerUp:Event,
	onPointerMove:Event,
	onPointerEnter:Event,
	onPointerLeave:Event,
	onPointerCancel:Event,
	onLostPointerCapture:Event,
	onWheel:Event,
	onKeyDown:Event,
	onKeyUp:Event,
	onTextInput:Event,
	onComposition:Event,
	// a field's text changed by its user (text: its text now)
	onInput:Event,
	onFocus:Event,
	onBlur:Event,
	onFocusIn:Event,
	onFocusOut:Event,
	onDragStart:Event,
	onDragOver:Event,
	onDragLeave:Event,
	onDrop:Event,
	onDragEnd:Event,
	// its laid-out size changed, and first laid out (target: its width and height); ui's only
	onResize:Event,
	// the gestures (helder.ui.gesture): the recogniser itself, reused
	onTap:Tap,
	onPan:Pan,
	// (two pointers' Scale; onScale's from one)
	onPinch:Scale,
	onScale:Scale
}
