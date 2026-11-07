package helder.ui;

// helder.ui for TypeScript programs (helder.typescript): windows and their
// markup (see helder/view), the events handlers are given, the keys. Each
// class is the Haxe class `__haxe` names. The neutral elements (view, text,
// view:button...) take any attribute, their handlers given ui's events.
@:typescript("helder/ui")
@:typescript.classes(helder.ui.draw.UiWindow, helder.ui.Event, helder.ui.Key, helder.ui.VirtualScroll, helder.ui.Clock, helder.ui.platform.WebViewEvent, helder.ui.platform.WebContent, helder.ui.platform.WebResponse)
@:typescript.functions(Surface = helder.ui.draw.UiWindow.Surface, VirtualList = helder.ui.view.UiFlow.VirtualList)
@:typescript.jsx(neutral)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
