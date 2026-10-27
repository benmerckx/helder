package helder.view;

// Implemented by a class whose markup literals are compiled (the build
// macro, MarkupMacro.build): <div>..</div> anywhere in its fields
@:autoBuild(helder.view.MarkupMacro.build())
interface Markup {}
