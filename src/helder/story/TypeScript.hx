package helder.story;

// helder.story for TypeScript programs (helder.typescript): story({name,
// render, seed, store, caption, background, color}), a definition (its
// fields checked where they are written, as Haxe's helder.story.Story.story;
// nothing in a release build), each story's view made from its Controls;
// tree(story), its tree mounted headless as helder test snapshots it
// (its markup helder.ui's: the neutral elements, its renderer); screens
// (stories), the studio's program of a project's screens (Screens); shots
// (stories), helder publish's program of its screenshots (StoreShots).
@:typescript("helder/story")
@:typescript.classes(helder.story.Story.Controls)
@:typescript.types(helder.story.Story)
@:typescript.functions(story = helder.story.Stories.define, tree = helder.story.Stories.tree, screens = helder.story.Screens.run, shots = helder.story.StoreShots.run)
@:typescript.imports("helder/view")
@:typescript.jsx(neutral)
@:typescript.renderers(helder.ui.view.NodeRenderer)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
