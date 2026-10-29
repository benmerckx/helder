package helder.web;

// The DOM's events, by attribute (DomRenderer's and StaticRenderer's
// @:events): what each handler is given, as TypeScript's lib.dom types
// them (onClick a MouseEvent, onKeyDown a KeyboardEvent, onInput an Event).
// Markup checks a handler against it: a function of this type or of none
// (onClick={() -> ...}), an untyped parameter typed by it; a name not here
// is no event, but for a custom one, on:name, of the field on's type (an
// Event). Outside JavaScript (the static renderer, natively or on Eval:
// no js.html there, its listeners dropped) each is Dynamic, so that code
// both builds compile types the same. Data, not code: helder.typescript's
// manifest and declarations read it.
typedef DomEvents = {
	// (on:name: a custom event's)
	on:DomEvent,
	onClick:DomMouseEvent,
	onDoubleClick:DomMouseEvent,
	onContextMenu:DomMouseEvent,
	onAuxClick:DomMouseEvent,
	onMouseDown:DomMouseEvent,
	onMouseUp:DomMouseEvent,
	onMouseMove:DomMouseEvent,
	onMouseEnter:DomMouseEvent,
	onMouseLeave:DomMouseEvent,
	onMouseOver:DomMouseEvent,
	onMouseOut:DomMouseEvent,
	onPointerDown:DomPointerEvent,
	onPointerUp:DomPointerEvent,
	onPointerMove:DomPointerEvent,
	onPointerEnter:DomPointerEvent,
	onPointerLeave:DomPointerEvent,
	onPointerOver:DomPointerEvent,
	onPointerOut:DomPointerEvent,
	onPointerCancel:DomPointerEvent,
	onGotPointerCapture:DomPointerEvent,
	onLostPointerCapture:DomPointerEvent,
	onTouchStart:DomTouchEvent,
	onTouchMove:DomTouchEvent,
	onTouchEnd:DomTouchEvent,
	onTouchCancel:DomTouchEvent,
	onWheel:DomWheelEvent,
	onKeyDown:DomKeyboardEvent,
	onKeyUp:DomKeyboardEvent,
	onKeyPress:DomKeyboardEvent,
	onFocus:DomFocusEvent,
	onBlur:DomFocusEvent,
	onFocusIn:DomFocusEvent,
	onFocusOut:DomFocusEvent,
	onBeforeInput:DomInputEvent,
	onInput:DomEvent,
	onChange:DomEvent,
	onSubmit:DomEvent,
	onReset:DomEvent,
	onInvalid:DomEvent,
	onSelect:DomEvent,
	onCompositionStart:DomCompositionEvent,
	onCompositionUpdate:DomCompositionEvent,
	onCompositionEnd:DomCompositionEvent,
	onCopy:DomClipboardEvent,
	onCut:DomClipboardEvent,
	onPaste:DomClipboardEvent,
	onDrag:DomDragEvent,
	onDragStart:DomDragEvent,
	onDragEnd:DomDragEvent,
	onDragEnter:DomDragEvent,
	onDragLeave:DomDragEvent,
	onDragOver:DomDragEvent,
	onDrop:DomDragEvent,
	onScroll:DomEvent,
	onLoad:DomEvent,
	onError:DomEvent,
	onToggle:DomEvent,
	onCancel:DomEvent,
	onClose:DomEvent,
	onAnimationStart:DomAnimationEvent,
	onAnimationEnd:DomAnimationEvent,
	onAnimationIteration:DomAnimationEvent,
	onTransitionStart:DomTransitionEvent,
	onTransitionEnd:DomTransitionEvent,
	onTransitionRun:DomTransitionEvent,
	onTransitionCancel:DomTransitionEvent,
	// (media's)
	onPlay:DomEvent,
	onPause:DomEvent,
	onEnded:DomEvent,
	onTimeUpdate:DomEvent,
	onVolumeChange:DomEvent,
	onLoadedData:DomEvent,
	onLoadedMetadata:DomEvent,
	onCanPlay:DomEvent,
	onSeeked:DomEvent,
	onWaiting:DomEvent
}

#if js
typedef DomEvent = js.html.Event;
typedef DomMouseEvent = js.html.MouseEvent;
typedef DomPointerEvent = js.html.PointerEvent;
typedef DomTouchEvent = js.html.TouchEvent;
typedef DomWheelEvent = js.html.WheelEvent;
typedef DomKeyboardEvent = js.html.KeyboardEvent;
typedef DomFocusEvent = js.html.FocusEvent;
typedef DomInputEvent = js.html.InputEvent;
typedef DomCompositionEvent = js.html.CompositionEvent;
typedef DomClipboardEvent = js.html.ClipboardEvent;
typedef DomDragEvent = js.html.DragEvent;
typedef DomAnimationEvent = js.html.AnimationEvent;
typedef DomTransitionEvent = js.html.TransitionEvent;
#else
typedef DomEvent = Dynamic;
typedef DomMouseEvent = Dynamic;
typedef DomPointerEvent = Dynamic;
typedef DomTouchEvent = Dynamic;
typedef DomWheelEvent = Dynamic;
typedef DomKeyboardEvent = Dynamic;
typedef DomFocusEvent = Dynamic;
typedef DomInputEvent = Dynamic;
typedef DomCompositionEvent = Dynamic;
typedef DomClipboardEvent = Dynamic;
typedef DomDragEvent = Dynamic;
typedef DomAnimationEvent = Dynamic;
typedef DomTransitionEvent = Dynamic;
#end
