package helder.view;

// A View of renderer R's markup (R: its class): a literal expected as one is
// compiled for R only, a component returning one is pinned to R (README,
// "Renderers in markup"). Packages name theirs: helder.ui.view.UiView.
@:typescript.input("unknown")
@:forward abstract ViewOf<R>(View) from View to View {}
