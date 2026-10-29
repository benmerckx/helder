package helder.view;

// The renderer contract: what markup and helder.view's runtime do to a tree
// of nodes. A renderer is a class of static functions over its node type N
// that implements Renders<N>, its nodes' class naming it (@:rendered(R));
// no define names it: a program reaches it when markup is compiled for it or
// content mounted into its nodes. Each place content is mounted in belongs
// to the renderer whose nodes it is (Render.render picks it by the parent's
// type), and everything mounted there, components included, is made by
// that renderer with direct, inlinable calls: markup is compiled for the
// renderer that owns it (or for each one reached), the runtime copied for
// each (ViewRuntime, HostMacro). A component that makes one renderer's node
// and renders into it with another is a boundary (a tag: <Scene>). The functions, checked when the renderer is first used:
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
//
// Optional: a macro giving the function that sets one property, named by a
// literal, (el, name, value): markup binds a reactive attribute with it
// instead of calling setProperty with the name, so that a renderer whose
// setProperty is a macro resolving literal names (ui's) links only the
// properties a program's markup names:
//
//   static macro function setter(name:String):Expr;
//
// Optional: a function markEnds (its body empty): a region that ends its
// parent gets a marker too, which hydration reads (the page's renderers:
// helder.web's DOM and static ones); without it such a region needs none.
//
//   static function markEnds():Void;
interface Renders<N> {}
