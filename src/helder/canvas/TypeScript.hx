package helder.canvas;

// helder.canvas for TypeScript programs (helder.typescript): the DOM's
// Canvas 2D (helder.canvas.dom), as skia-canvas and @napi-rs/canvas have
// it, so code written for the browser's canvas runs natively. Each class
// is the Haxe class `__haxe` names.
@:typescript("helder/canvas")
@:typescript.classes(helder.canvas.dom.Canvas, helder.canvas.dom.CanvasRenderingContext2D, helder.canvas.dom.Path2D, helder.canvas.dom.CanvasGradient,
	helder.canvas.dom.CanvasPattern, helder.canvas.dom.ImageData, helder.canvas.dom.DOMMatrix, helder.canvas.dom.Image, helder.canvas.dom.TextMetrics,
	helder.canvas.dom.FontLibrary)
@:typescript.functions(loadImage = helder.canvas.dom.Image.load)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
