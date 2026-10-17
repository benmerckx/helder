package hxmc.view;

// The renderer this program's markup and hxmc.view's runtime call (Renders):
// the class -D hxmc.view.renderer names, so that Host.insert(...) is a
// direct call to it
#if !macro
@:genericBuild(hxmc.view.HostMacro.renderer())
#end
class Host {}
