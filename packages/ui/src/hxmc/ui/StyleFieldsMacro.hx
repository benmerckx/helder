package hxmc.ui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// StyleFields's NAMES, get and set: for each field of StyleProps that is a
// property of Style both readable and writable (shorthands such as flex,
// gap and outline are written only, through their longhands)
class StyleFieldsMacro {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var props = switch Context.follow(Context.getType("hxmc.ui.StyleProps")) {
			case TAnonymous(a): [for (f in a.get().fields) f.name];
			case _: throw "StyleProps";
		}
		var style = switch Context.getType("hxmc.ui.Style") {
			case TInst(c, _): c.get();
			case _: throw "Style";
		}
		var names:Array<String> = [];
		for (f in style.fields.get()) {
			if (!f.isPublic || props.indexOf(f.name) < 0) continue;
			switch f.kind {
				case FVar(read, write):
					if (read == AccNever || read == AccNo || write == AccNever || write == AccNo) continue;
				case _:
					continue;
			}
			names.push(f.name);
		}
		var getCases:Array<Case> = [for (n in names) {values: [macro $v{n}], expr: macro s.$n}];
		var setCases:Array<Case> = [for (n in names) {values: [macro $v{n}], expr: macro s.$n = v}];
		var pos = Context.currentPos();
		var nameExprs:Array<Expr> = [for (n in names) macro $v{n}];
		fields.push({
			name: "NAMES",
			access: [APublic, AStatic, AFinal],
			pos: pos,
			kind: FVar(macro :Array<String>, macro $a{nameExprs})
		});
		fields.push({
			name: "get",
			access: [APublic, AStatic],
			pos: pos,
			kind: FFun({
				args: [{name: "s", type: macro :hxmc.ui.Style}, {name: "name", type: macro :String}],
				ret: macro :Dynamic,
				expr: macro return ${{expr: ESwitch(macro name, getCases, macro null), pos: pos}}
			})
		});
		fields.push({
			name: "set",
			access: [APublic, AStatic],
			pos: pos,
			kind: FFun({
				args: [
					{name: "s", type: macro :hxmc.ui.Style},
					{name: "name", type: macro :String},
					{name: "v", type: macro :Dynamic}
				],
				ret: macro :Void,
				expr: {expr: ESwitch(macro name, setCases, macro {}), pos: pos}
			})
		});
		return fields;
	}
}
#end
