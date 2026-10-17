package hxmc.view;

import haxe.macro.Expr;

// A markup literal's value: what mounts its nodes. Write markup in a class
// that implements Markup (every literal in it is compiled), or through
// view(<...>):
//
//   class App implements Markup {
//     static function main()
//       Render.render(<view padding={8}>
//         <text>Hello {name}!</text>
//         {[for (i in items) <text>{i}</text>]}
//         <Button label="OK" onClick={() -> trace("ok")}/>
//       </view>, root);
//   }
//
// The literal's holes ({expr} children and attribute values) are evaluated
// where it is; mount then makes its elements (the renderer's, by tag:
// lowercase names), sets their attributes and inserts them, each time it is
// mounted. Other names are components: Button(props) called when mounted,
// untracked, in an owner of its own, props an object of its attributes
// (children: the content, a View), checked against Button's argument.
class View {
	#if !macro
	// makes the nodes in parent before before (null: at the end); the top
	// ones also pushed to out (when not null)
	public final mount:(parent:HostNode, before:Null<HostNode>, out:Null<Array<HostNode>>) -> Void;
	// content of components, holes and fragments only (a Switch's Match
	// cases): its parts as values, components called (null: it has elements
	// or text)
	public final parts:Null<Void->Array<Any>>;
	// where the literal is: file:line
	public final source:String;

	public function new(mount, parts, source) {
		this.mount = mount;
		this.parts = parts;
		this.source = source;
	}

	public function toString():String
		return 'View($source)';
	#end

	// compiles a markup literal: View.view(<view>{x}</view>)
	public static macro function view(e:Expr):Expr
		return hxmc.view.MarkupMacro.transform(e);
}
