package hxmc.view;

// Implemented by a class whose markup literals are compiled (the build
// macro, MarkupMacro.build): <div>..</div> anywhere in its fields
@:autoBuild(hxmc.view.MarkupMacro.build())
interface Markup {}
