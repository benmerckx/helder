package hxmc.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// Host and HostNode: the renderer -D hxmc.view.renderer names and its node
// type (the N of its Renders<N>), its functions checked against the
// contract once
class HostMacro {
	static final REQUIRED = [
		"createElement", "createText", "createMarker", "setText", "holdsText", "setProperty", "setStyle", "listen", "insert", "remove", "parentOf",
		"arrange", "isNode"
	];

	static var checked:Null<String> = null;

	public static function renderer():ComplexType {
		var path = name();
		var parts = path.split(".");
		var cls = parts.pop();
		return TPath({pack: parts, name: cls});
	}

	public static function node():ComplexType {
		var c = renderClass();
		for (i in c.interfaces)
			if (i.t.toString() == "hxmc.view.Renders") return Context.toComplexType(i.params[0]);
		return Context.fatalError('hxmc.view: the renderer ${c.name} does not implement hxmc.view.Renders<Node>', c.pos);
	}

	static function name():String {
		var path = Context.definedValue("hxmc.view.renderer");
		if (path == null || path == "" || path == "1")
			Context.fatalError("hxmc.view: no renderer: name one with -D hxmc.view.renderer=<class> (-lib hxmc.ui sets hxmc.ui.view.NodeRenderer)",
				Context.currentPos());
		return path;
	}

	static function renderClass():ClassType {
		var path = name();
		var c = switch Context.getType(path) {
			case TInst(c, _): c.get();
			case _: Context.fatalError('hxmc.view: the renderer $path is not a class', Context.currentPos());
		}
		if (checked != path) {
			checked = path;
			var have = [for (f in c.statics.get()) f.name => true];
			var missing = [for (r in REQUIRED) if (!have.exists(r)) r];
			if (missing.length > 0) Context.fatalError('hxmc.view: the renderer $path lacks ' + missing.join(", ") + " (hxmc.view.Renders)", c.pos);
		}
		return c;
	}
}
#end
