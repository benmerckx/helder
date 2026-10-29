package helder.view;

// helder.view for TypeScript programs (helder.typescript): signals,
// computations, markup (TSX) and its control flow, on helder.view.graph
// (DESIGN.md). Each class is the Haxe class `__haxe` names; a function is one
// of a class's statics (typeof Class.name), called directly by the compiled
// program, its values converted by the types Haxe declares (the manifest,
// DESIGN.md 7.3); a signal, a memo or a Read comes to the program as a
// function.
@:typescript("helder/view")
@:typescript.types(helder.view.graph.Signal, helder.view.graph.Memo, helder.view.graph.Read, helder.view.View)
@:typescript.classes(helder.view.Render)
@:typescript.functions(signal = helder.view.graph.Graph.signalValue, memo = helder.view.graph.Graph.memo, effect = helder.view.graph.Graph.effect,
	renderEffect = helder.view.graph.Graph.renderEffect, flush = helder.view.graph.Scheduler.flush, untrack = helder.view.graph.Graph.untrack,
	root = helder.view.graph.Graph.root, onCleanup = helder.view.graph.Graph.onCleanup, onSettled = helder.view.graph.Graph.onSettled,
	isPending = helder.view.graph.Graph.isPending, For = helder.view.Flow.For, Repeat = helder.view.Flow.Repeat, Show = helder.view.Flow.Show,
	Switch = helder.view.Flow.Switch, Match = helder.view.Flow.Match, Loading = helder.view.Flow.Loading, Errored = helder.view.Flow.Errored)
@:typescript.jsx(base)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
