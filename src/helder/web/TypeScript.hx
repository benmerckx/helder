package helder.web;

// helder.web for TypeScript programs (helder.typescript): static pages
// rendered at build time, with islands of WebAssembly (see helder/view; the
// web's elements are lower-case TSX, their attributes as helder.web's
// README has them). Each class is the Haxe class `__haxe` names.
@:typescript("helder/web")
@:typescript.types(helder.web.Island.Load, helder.web.Island.Stop)
@:typescript.classes(helder.web.Static, helder.web.Island, helder.web.WebTags)
@:typescript.functions(Surface = helder.web.WebTags.Surface)
@:typescript.renderers(helder.web.StaticRenderer)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
