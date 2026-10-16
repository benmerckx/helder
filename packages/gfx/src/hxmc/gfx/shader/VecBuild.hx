package hxmc.gfx.shader;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

// The members of the math types written out by a macro, each a small
// inline function (so that CPU code pays nothing for them):
//
//   vector(n)   Vec<n>'s operators (+ - * / componentwise; with a Float on
//               either side; unary -) and its swizzles of 2 to 4 components
//               (v.yx, v.xyy, v.wzyx), read only
//   builtins()  ShaderMath's functions: the vector constructors, GLSL's
//               componentwise functions (abs, floor, mix, clamp, ...) and the
//               geometric ones (dot, length, normalize, cross, ...), an
//               overload per type
//
// The shader macro (Lower) knows them by name, so the names here are part
// of its interface.
class VecBuild {
	static final XYZW = ["x", "y", "z", "w"];

	public static function vector(n:Int):Array<Field> {
		var fields = Context.getBuildFields();
		var self = 'Vec$n', c = XYZW.slice(0, n);
		// componentwise: one expression per component, $ standing for it
		function each(f:String):String
			return 'new $self(' + [for (k in c) StringTools.replace(f, "$", k)].join(", ") + ")";
		function op(name, op, args:Array<Array<String>>, body, commutative = false)
			fields.push(fn(name, args, self, body, [{name: ":op", params: [Context.parse(op, Context.currentPos())], pos: Context.currentPos()}]
				.concat(commutative ? [{name: ":commutative", params: [], pos: Context.currentPos()}] : [])));
		var vv = [["a", self], ["b", self]], vs = [["a", self], ["s", "Float"]], sv = [["s", "Float"], ["a", self]];
		op("add", "A + B", vv, each("a.$ + b.$"));
		op("sub", "A - B", vv, each("a.$ - b.$"));
		op("mul", "A * B", vv, each("a.$ * b.$"));
		op("div", "A / B", vv, each("a.$ / b.$"));
		op("adds", "A + B", vs, each("a.$ + s"), true);
		op("subs", "A - B", vs, each("a.$ - s"));
		op("ssub", "A - B", sv, each("s - a.$"));
		op("scale", "A * B", vs, each("a.$ * s"), true);
		op("divs", "A / B", vs, each("a.$ / s"));
		op("sdiv", "A / B", sv, each("s / a.$"));
		op("neg", "-A", [["a", self]], each("-a.$"));
		// swizzles: every sequence of 2 to 4 of the components
		function swizzles(prefix:String, len:Int) {
			if (prefix.length == len) {
				var t = 'Vec$len';
				fields.push({
					name: prefix,
					access: [APublic],
					kind: FProp("get", "never", ct(t)),
					pos: Context.currentPos()
				});
				var get = fn("get_" + prefix, [], t, 'new $t(' + [for (i in 0...len) "this." + prefix.charAt(i)].join(", ") + ")");
				get.access = [AInline];
				get.meta = [{name: ":noCompletion", pos: get.pos}];
				fields.push(get);
				return;
			}
			for (k in c)
				swizzles(prefix + k, len);
		}
		for (len in 2...5)
			swizzles("", len);
		return fields;
	}

	public static function builtins():Array<Field> {
		var fields = Context.getBuildFields();
		function add(name, args:Array<Array<String>>, ret, body) {
			var f = fn(name, args, ret, body);
			f.access = [APublic, AStatic, AOverload, AExtern, AInline];
			fields.push(f);
		}
		// componentwise over the vector types, from the Float version
		function each(name:String, args:Array<Array<String>>, ret:String, n:Int) {
			var self = 'Vec$n', comps = XYZW.slice(0, n);
			var vargs = [for (a in args) [a[0], a[1] == "T" ? self : a[1]]];
			var call = (k:String) -> name + "(" + [for (a in args) a[1] == "T" ? a[0] + "." + k : a[0]].join(", ") + ")";
			add(name, vargs, ret == "T" ? self : ret, 'new $self(' + [for (k in comps) call(k)].join(", ") + ")");
		}
		function generic(name:String, args:Array<Array<String>>, scalar:String) {
			add(name, [for (a in args) [a[0], a[1] == "T" ? "Float" : a[1]]], "Float", scalar);
			for (n in 2...5)
				each(name, args, "T", n);
		}
		for (f in [
			["abs", "Math.abs(x)"], ["sign", "x > 0 ? 1.0 : x < 0 ? -1.0 : 0.0"], ["floor", "Math.ffloor(x)"], ["ceil", "Math.fceil(x)"],
			["fract", "x - Math.ffloor(x)"], ["sqrt", "Math.sqrt(x)"], ["inversesqrt", "1 / Math.sqrt(x)"], ["sin", "Math.sin(x)"], ["cos", "Math.cos(x)"],
			["tan", "Math.tan(x)"], ["exp", "Math.exp(x)"], ["log", "Math.log(x)"]
		])
			generic(f[0], [["x", "T"]], f[1]);
		for (f in [
			["min", "Math.min(x, y)"], ["max", "Math.max(x, y)"], ["pow", "Math.pow(x, y)"]
		])
			generic(f[0], [["x", "T"], ["y", "T"]], f[1]);
		generic("step", [["edge", "T"], ["x", "T"]], "x < edge ? 0.0 : 1.0");
		generic("mix", [["x", "T"], ["y", "T"], ["a", "T"]], "x + (y - x) * a");
		generic("clamp", [["x", "T"], ["lo", "T"], ["hi", "T"]], "Math.min(Math.max(x, lo), hi)");
		generic("smoothstep", [["e0", "T"], ["e1", "T"], ["x", "T"]], "{var t = clamp((x - e0) / (e1 - e0), 0.0, 1.0); t * t * (3 - 2 * t);}");
		for (n in 2...5) {
			// the forms with Float bounds or weights
			each("mix", [["x", "T"], ["y", "T"], ["a", "Float"]], "T", n);
			each("clamp", [["x", "T"], ["lo", "Float"], ["hi", "Float"]], "T", n);
			each("smoothstep", [["e0", "Float"], ["e1", "Float"], ["x", "T"]], "T", n);
			var t = 'Vec$n', comps = XYZW.slice(0, n);
			var dot = [for (k in comps) 'a.$k * b.$k'].join(" + ");
			add("dot", [["a", t], ["b", t]], "Float", dot);
			add("length", [["a", t]], "Float", 'Math.sqrt($dot)'.split("b.").join("a."));
			add("distance", [["a", t], ["b", t]], "Float", "length(a - b)");
			add("normalize", [["a", t]], t, "a / length(a)");
			add("reflect", [["i", t], ["n", t]], t, "i - n * (2 * dot(n, i))");
		}
		add("cross", [["a", "Vec3"], ["b", "Vec3"]], "Vec3", "new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)");
		// constructors
		add("vec2", [["x", "Float"], ["y", "Float"]], "Vec2", "new Vec2(x, y)");
		add("vec2", [["s", "Float"]], "Vec2", "new Vec2(s, s)");
		add("vec3", [["x", "Float"], ["y", "Float"], ["z", "Float"]], "Vec3", "new Vec3(x, y, z)");
		add("vec3", [["xy", "Vec2"], ["z", "Float"]], "Vec3", "new Vec3(xy.x, xy.y, z)");
		add("vec3", [["x", "Float"], ["yz", "Vec2"]], "Vec3", "new Vec3(x, yz.x, yz.y)");
		add("vec3", [["s", "Float"]], "Vec3", "new Vec3(s, s, s)");
		add("vec4", [["x", "Float"], ["y", "Float"], ["z", "Float"], ["w", "Float"]], "Vec4", "new Vec4(x, y, z, w)");
		add("vec4", [["xyz", "Vec3"], ["w", "Float"]], "Vec4", "new Vec4(xyz.x, xyz.y, xyz.z, w)");
		add("vec4", [["x", "Float"], ["yzw", "Vec3"]], "Vec4", "new Vec4(x, yzw.x, yzw.y, yzw.z)");
		add("vec4", [["xy", "Vec2"], ["z", "Float"], ["w", "Float"]], "Vec4", "new Vec4(xy.x, xy.y, z, w)");
		add("vec4", [["xy", "Vec2"], ["zw", "Vec2"]], "Vec4", "new Vec4(xy.x, xy.y, zw.x, zw.y)");
		add("vec4", [["s", "Float"]], "Vec4", "new Vec4(s, s, s, s)");
		add("mat4", [["c0", "Vec4"], ["c1", "Vec4"], ["c2", "Vec4"], ["c3", "Vec4"]], "Mat4", "new Mat4(c0, c1, c2, c3)");
		// (the diagonal: mat4(1) is the identity)
		add("mat4", [["s", "Float"]], "Mat4", "new Mat4(new Vec4(s, 0, 0, 0), new Vec4(0, s, 0, 0), new Vec4(0, 0, s, 0), new Vec4(0, 0, 0, s))");
		return fields;
	}

	static function ct(name:String):ComplexType
		return name == "Float" ? macro :Float : TPath({pack: ["hxmc", "gfx", "shader"], name: name});

	static function fn(name:String, args:Array<Array<String>>, ret:String, body:String, ?meta:Metadata):Field {
		var pos = Context.currentPos();
		return {
			name: name,
			access: [AStatic, AInline],
			meta: meta,
			kind: FFun({args: [for (a in args) {name: a[0], type: ct(a[1])}], ret: ct(ret), expr: macro return ${Context.parse(body, pos)}}),
			pos: pos
		};
	}
}
#end
