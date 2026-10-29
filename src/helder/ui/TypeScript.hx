package helder.ui;

// helder.ui for TypeScript programs (helder.typescript): windows and their
// markup (see helder/view), the events handlers are given, the keys. Each
// class is the Haxe class `__haxe` names. The neutral elements (view, text,
// view:button...) take any attribute, their handlers given ui's events.
@:typescript("helder/ui")
@:typescript.classes(helder.ui.draw.UiWindow, helder.ui.Event, helder.ui.Key)
@:typescript.functions(Surface = helder.ui.draw.UiWindow.Surface)
@:typescript.jsx(neutral)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
