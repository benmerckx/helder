package helder.view;

// The root: content with no parent (a program's: Render.open, App.run),
// components only, each making roots of its own (<Surface>: a window, a
// canvas). Not a renderer, no nodes: what RootView pins its components to,
// so that a <Surface> in a renderer's markup is an error.
class Root {}
