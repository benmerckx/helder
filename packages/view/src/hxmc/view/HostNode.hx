package hxmc.view;

// The node type of the program's renderer (Host): the N of its Renders<N>
#if !macro
@:genericBuild(hxmc.view.HostMacro.node())
#end
class HostNode {}
