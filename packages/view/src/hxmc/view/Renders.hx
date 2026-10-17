package hxmc.view;

// The renderer contract: what markup and hxmc.view's runtime do to a tree
// of nodes. A renderer is a class of static functions over its node type N
// that implements Renders<N>; a program names its renderer with
// -D hxmc.view.renderer=<class> (@hxmc/ui's hxmc.ui.view.NodeRenderer is
// set by -lib hxmc.ui), and every call to it is a direct, inlinable call
// (Host is that class, HostNode its N). The functions, checked when the
// renderer is first used (HostMacro):
//
//   // nodes
//   static function createElement(tag:String):N;
//   static function createText(text:String):N;
//   // an invisible node marking where content goes (before it): a region's,
//   // a list's (ui: a hidden node; the DOM: a comment)
//   static function createMarker(name:String):N;
//   // a text node's text, or the own text of an element that holdsText
//   static function setText(node:N, text:String):Void;
//   // whether an element takes its text children as its own text (setText)
//   // and its child elements as spans (ui's TextNode; the DOM: never)
//   static function holdsText(el:N):Bool;
//   // attributes: a property or attribute, the style, a listener (on*)
//   static function setProperty(el:N, name:String, value:Dynamic):Void;
//   static function setStyle(el:N, value:Dynamic):Void;
//   static function listen(el:N, name:String, handler:Dynamic):Void;
//   // the tree: node put before before (null: at the end; moved when it is
//   // already in parent), removed, its parent; nodes (children of parent)
//   // put in that order just before before (a keyed list's rows)
//   static function insert(parent:N, node:N, before:Null<N>):Void;
//   static function remove(parent:N, node:N):Void;
//   static function parentOf(node:N):Null<N>;
//   static function arrange(parent:N, nodes:Array<N>, before:N):Void;
//   // content that is a node already (rendered as it is)
//   static function isNode(v:Dynamic):Bool;
interface Renders<N> {}
