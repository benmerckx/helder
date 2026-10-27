package helder.view;

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
// mounted, by the renderer that owns the place it is mounted in (each
// literal is compiled for the renderer that owns it, or for each the
// program reaches). Other names
// are components: Button(props) called when mounted, untracked, in an
// owner of its own, props an object of its attributes (children: the
// content, a View), checked against Button's argument.
class View {
	#if !macro
	// the renderer its code is for (Render.idOf: a hash of its class), or 0:
	// any the program reaches (an agnostic literal: its code for each made
	// after typing, found by its key: ViewRuntime's late)
	public final renderer:Int;
	// its code: makes its nodes in parent before before (null: at the end),
	// the top ones also pushed to out (when not null); parent, before and out
	// are its renderer's nodes (null: agnostic)
	public final mount:Null<(parent:Dynamic, before:Dynamic, out:Dynamic) -> Void>;
	// an agnostic literal's key and the values of its holes
	public final key:Int;
	public final holes:Null<Array<Any>>;
	// content of components, holes and fragments only (a Switch's Match
	// cases): its parts as values, components called (null: it has elements
	// or text)
	public final parts:Null<Void->Array<Any>>;
	// where the literal is: file:line
	public final source:String;

	public function new(renderer, mount, key, holes, parts, source) {
		this.renderer = renderer;
		this.mount = mount;
		this.key = key;
		this.holes = holes;
		this.parts = parts;
		this.source = source;
	}

	public function toString():String
		return 'View($source)';
	#end

	// compiles a markup literal: View.view(<view>{x}</view>)
	public static macro function view(e:Expr):Expr
		return helder.view.MarkupMacro.transform(e);

	// (a literal, wrapped by Markup's build macro: compiled when typed, for the renderer where it is)
	@:noCompletion public static macro function literal(e:Expr):Expr
		return helder.view.MarkupMacro.literal(e, null);

	// (a literal for the renderer of the class path given: inside its markup)
	@:noCompletion public static macro function literalFor(renderer:String, e:Expr):Expr
		return helder.view.MarkupMacro.literal(e, renderer);
}

