package helder.jobs;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.TypeTools;

// What can be sent to another thread or a browser's worker (as Swift's
// Sendable): a GC job's argument and result, a Channel's values. Checked
// at compile time (the culprit named, with where it is in the type), and
// each one's codec generated (Wire):
//
//   Int, Float, Bool, haxe.Int64      copied
//   String, haxe.io.Bytes             copied (null too)
//   hxmc.unsafe.IoBuffer              moved: natively its address, in a browser its bytes (the sender's freed)
//   @:hxmc.struct classes             copied (their bytes)
//   Null<T>, abstracts over a T       as T (enum abstracts included)
//   { a:T, ... }, Array<T>            copied, field by field, element by element
//   Channel<T>                        the channel itself (its id)
//
// Not: classes and interfaces (shared mutable state), enums, functions,
// Dynamic, Ptr (an address means nothing in another instance), type
// parameters, Map, recursive types.
class Sendable {
	static inline var WHAT = "flat values, String, Bytes, IoBuffer, hxmc structs, and anonymous structures, Arrays and Channels of these";

	// ---- the check

	// why t cannot be sent (where in t, and what), or null
	public static function reason(t:Type):Null<String>
		return why(t, "", []);

	static function why(t:Type, at:String, seen:Array<String>):Null<String> {
		var here = at == "" ? "" : at + ": ";
		switch kind(t) {
			case Bad(m):
				return here + TypeTools.toString(t) + " is " + m;
			case Nullable(i), Under(i, _):
				return why(i, at, seen);
			case List(e):
				return why(e, at + "[]", seen);
			case Fields(fs):
				var key = TypeTools.toString(t);
				if (seen.contains(key)) return here + key + " is recursive";
				seen.push(key);
				for (f in fs) {
					var r = why(f.type, at + "." + f.name, seen);
					if (r != null) return r;
				}
				seen.pop();
				return null;
			case _:
				return null;
		}
	}

	static function check(t:Type, what:String, pos:Position) {
		var r = reason(t);
		if (r != null) Context.error('helder.jobs: $what cannot be sent: $r (sendable: $WHAT)', pos);
	}

	// ---- the codec

	// an expression writing v (of type t) to the Writer w
	public static function write(t:Type, w:Expr, v:Expr):Expr {
		return switch kind(t) {
			case IntK: macro $w.int($v);
			case FloatK: macro $w.float($v);
			case BoolK: macro $w.bool($v);
			case Int64K: macro $w.int64($v);
			case StringK: macro $w.string($v);
			case BytesK: macro $w.bytes($v);
			case BufferK: macro $w.buffer($v);
			case StructK(c):
				var ct = TypeTools.toComplexType(t), cls = classExpr(c);
				macro {
					var p:hxmc.unsafe.Ptr<$ct> = cast $w.reserve(hxmc.unsafe.Struct.sizeOf($cls));
					p.value = $v;
				};
			case ChannelK(_): macro $w.int($v.id);
			case Nullable(i):
				switch kind(i) {
					case StringK, BytesK, List(_), Fields(_), ChannelK(_): write(i, w, v);
					case _:
						var ct = TypeTools.toComplexType(i);
						macro {
							var n = $v;
							$w.bool(n != null);
							if (n != null) ${write(i, w, macro(n : $ct))};
						};
				}
			case Under(i, _):
				var ct = TypeTools.toComplexType(i);
				write(i, w, macro(cast $v : $ct));
			case List(e):
				var x = macro x;
				macro {
					var a = $v;
					if (a == null) $w.int(-1) else {
						$w.int(a.length);
						for (x in a)
							${write(e, w, x)};
					}
				};
			case Fields(fs):
				var each = [for (f in fs) write(f.type, w, field(macro o, f.name))];
				macro {
					var o = $v;
					$w.bool(o != null);
					if (o != null) $b{each};
				};
			case Bad(_): throw "unreachable";
		}
	}

	// an expression reading a t from the Reader r
	public static function read(t:Type, r:Expr):Expr {
		var ct = TypeTools.toComplexType(t);
		return switch kind(t) {
			case IntK: macro $r.int();
			case FloatK: macro $r.float();
			case BoolK: macro $r.bool();
			case Int64K: macro $r.int64();
			case StringK: macro $r.string();
			case BytesK: macro $r.bytes();
			case BufferK: macro $r.buffer();
			case StructK(c):
				var cls = classExpr(c);
				macro {
					var p:hxmc.unsafe.Ptr<$ct> = cast $r.at(hxmc.unsafe.Struct.sizeOf($cls));
					p.value;
				};
			case ChannelK(c): macro ${classExpr(c)}.of($r.int());
			case Nullable(i):
				switch kind(i) {
					case StringK, BytesK, List(_), Fields(_), ChannelK(_): read(i, r);
					case _: macro($r.bool() ? ${read(i, r)} : null : $ct);
				}
			case Under(i, _): macro(cast ${read(i, r)} : $ct);
			case List(e):
				macro({
					var n = $r.int();
					n < 0 ? null : [for (_ in 0...n) ${read(e, r)}];
				} : $ct);
			case Fields(fs):
				var obj:Expr = {expr: EObjectDecl([for (f in fs) {field: f.name, expr: read(f.type, r)}]), pos: Context.currentPos()};
				macro($r.bool() ? $obj : null : $ct);
			case Bad(_): throw "unreachable";
		}
	}

	static function field(e:Expr, name:String):Expr
		return {expr: EField(e, name), pos: e.pos};

	static function classExpr(c:ClassType):Expr {
		var parts = c.module.split(".");
		if (parts[parts.length - 1] != c.name) parts.push(c.name);
		return macro $p{parts};
	}

	// ---- what a type is

	static function kind(t:Type):Kind {
		switch t {
			case TMono(r) if (r.get() == null):
				return Bad("not known yet (give the type)");
			case TMono(r):
				return kind(r.get());
			case TLazy(f):
				return kind(f());
			case TType(_, _):
				return kind(Context.follow(t, true));
			case TAbstract(a, params):
				var at = a.get(), path = at.pack.concat([at.name]).join(".");
				switch path {
					case "Int": return IntK;
					case "Float": return FloatK;
					case "Bool": return BoolK;
					case "haxe.Int64": return Int64K;
					case "Null": return Nullable(params[0]);
					case "hxmc.unsafe.IoBuffer": return BufferK;
					case "hxmc.unsafe.Ptr": return Bad("an address (it means nothing in another instance: an IoBuffer moves)");
					case "Void": return Bad("Void");
					case "Dynamic", "Any": return Bad("dynamic");
					case _:
				}
				if (at.meta.has(":coreType")) return Bad("a core type");
				var under = at.type.applyTypeParameters(at.params, params);
				return Under(under, t);
			case TInst(c, params):
				var ct = c.get(), path = ct.pack.concat([ct.name]).join(".");
				switch path {
					case "String": return StringK;
					case "haxe.io.Bytes": return BytesK;
					case "Array": return List(params[0]);
					case _:
				}
				switch ct.kind {
					case KTypeParameter(_): return Bad("a type parameter (not known to be sendable)");
					case _:
				}
				if (ct.meta.has(":hxmc.struct")) return StructK(ct);
				var s = ct.superClass;
				if (s != null && s.t.get().name == "ChannelBase" && s.t.get().pack.join(".") == "helder.jobs") return ChannelK(ct);
				return Bad(ct.isInterface ? "an interface (shared mutable state)" : "a class (shared mutable state)");
			case TAnonymous(a):
				var fs = a.get().fields.copy();
				fs.sort((x, y) -> x.name < y.name ? -1 : 1);
				for (f in fs) switch f.kind {
					case FMethod(_): return Bad("an object with methods");
					case _:
				}
				return Fields([for (f in fs) {name: f.name, type: f.type}]);
			case TEnum(_, _):
				return Bad("an enum (not yet)");
			case TFun(_, _):
				return Bad("a function");
			case TDynamic(_):
				return Bad("dynamic");
		}
	}

	// ---- Jobs.run

	public static function job(f:Expr, rest:Array<Expr>):Expr {
		var pos = Context.currentPos();
		if (rest.length > 1) Context.error("Jobs.run: a job takes one input at most", rest[1].pos);
		var typed = Context.typeExpr(f);
		var c:ClassType, cf:ClassField;
		switch typed.expr {
			case TField(_, FStatic(cr, fr)):
				c = cr.get();
				cf = fr.get();
			case _:
				Context.error("Jobs.run: a job is a static function, named (Class.field)", f.pos);
				return null;
		}
		var fpath = field(classExpr(c), cf.name);
		if (cf.params.length > 0) Context.error('Jobs.run: ${cf.name} has type parameters (its values\' types must be known)', f.pos);
		var input = rest.length > 0 ? rest[0] : null;
		// GC-free: an @:hxmc.unsafe callback (job:Job):Int
		if (cf.meta.has(":hxmc.unsafe")) {
			if (!cf.meta.has(":hxmc.callback") || !Context.unify(cf.type, Context.resolveType(macro:helder.jobs.Job->Int, f.pos)))
				Context.error('Jobs.run: a GC-free job is an @:hxmc.unsafe @:hxmc.callback static function (job:helder.jobs.Job):Int (${cf.name})', f.pos);
			var i = input ?? macro cast hxmc.unsafe.Ptr.nil();
			return macro @:pos(pos) helder.jobs.Jobs.runFree(hxmc.unsafe.Callback.addr($fpath), ($i : hxmc.unsafe.IoBuffer));
		}
		// a GC job: (input) -> result, both sendable
		var args, ret;
		switch Context.follow(cf.type) {
			case TFun(a, r):
				args = a;
				ret = r;
			case _:
				Context.error("Jobs.run: a job is a static function", f.pos);
				return null;
		}
		if (args.length > 1) Context.error('Jobs.run: ${cf.name} takes ${args.length} arguments (a job takes one at most: an anonymous structure for more)', f.pos);
		if (args.length == 1 && input == null) Context.error('Jobs.run: ${cf.name} takes an input', pos);
		if (args.length == 0 && input != null) Context.error('Jobs.run: ${cf.name} takes no input', input.pos);
		if (args.length == 1) check(args[0].t, '${cf.name}\'s input', input.pos);
		var void = switch Context.follow(ret) {
			case TAbstract(_.get() => {name: "Void", pack: []}, _): true;
			case _: false;
		}
		if (!void) check(ret, '${cf.name}\'s result', f.pos);
		// (its wrapper: a callback, its input read and its result written)
		var name = "Job_" + c.module.split(".").join("_") + (c.module.split(".").pop() != c.name ? "_" + c.name : "") + "_" + cf.name;
		if (!defined(name)) {
			// (the call site could name it: private too)
			var call = args.length == 1 ? macro @:privateAccess $fpath(${read(args[0].t, macro r)}) : macro @:privateAccess $fpath();
			var body = if (void) macro {
				$call;
				0;
			} else macro {
				var v = $call;
				var w = new helder.jobs.Wire.Writer();
				${write(ret, macro w, macro v)};
				job.setOutput(w.done());
				0;
			}
			var head = args.length == 1 ? macro var r = new helder.jobs.Wire.Reader(job.input) : macro {};
			var td = macro class $name {
				@:hxmc.callback public static function run(p:hxmc.unsafe.Ptr):Int {
					var job:helder.jobs.Job = cast p;
					return try {
						$head;
						$body;
					} catch (e:Dynamic) helder.jobs.Jobs.failed(job, e);
				}
			};
			td.pack = ["helder", "jobs", "gen"];
			td.pos = f.pos;
			Context.defineType(td);
		}
		var gen = macro $p{["helder", "jobs", "gen", name, "run"]};
		var i = if (args.length == 1) {
			var ct = TypeTools.toComplexType(args[0].t);
			macro {
				var w = new helder.jobs.Wire.Writer();
				var v:$ct = $input;
				${write(args[0].t, macro w, macro v)};
				w.done();
			};
		} else macro cast hxmc.unsafe.Ptr.nil();
		if (void) return macro @:pos(pos) helder.jobs.Jobs.runGcVoid(hxmc.unsafe.Callback.addr($gen), $i);
		var rt = TypeTools.toComplexType(ret);
		return macro @:pos(pos) {
			var out = helder.jobs.Jobs.runGc(hxmc.unsafe.Callback.addr($gen), $i);
			var r = new helder.jobs.Wire.Reader(out);
			var v:$rt = ${read(ret, macro r)};
			helder.jobs.Jobs.free(out);
			v;
		};
	}

	static function defined(name:String):Bool
		return try Context.getType("helder.jobs.gen." + name) != null catch (_:Dynamic) false;

	// ---- Channel<T>

	public static function channel():ComplexType {
		var pos = Context.currentPos();
		var t = switch Context.getLocalType() {
			case TInst(_, [t]): t;
			case _:
				Context.error("Channel: Channel<T>, its values' type T", pos);
				return null;
		}
		check(t, "a Channel's value", pos);
		var ct = TypeTools.toComplexType(t);
		var name = "Channel_" + Context.signature(TypeTools.toString(t)).substr(0, 16);
		if (!defined(name)) {
			var path = {pack: ["helder", "jobs", "gen"], name: name};
			var self = TPath(path);
			var td = macro class $name extends helder.jobs.ChannelBase {
				// a channel this thread receives from
				public function new(?remote:Int)
					super(remote);

				// v to the receiver (from any thread or job; a JobError once closed)
				public function send(v:$ct):Void {
					var w = new helder.jobs.Wire.Writer();
					${write(t, macro w, macro v)};
					push(w.done());
				}

				// the next value, in order; null once closed and every value sent received
				@:coroutine public function receive():Null<$ct> {
					var b = take();
					if (b == null) return null;
					var r = new helder.jobs.Wire.Reader(b);
					var v = ${read(t, macro r)};
					b.free();
					return v;
				}

				// (Sendable's: the channel of that id, a stand-in where it is not: a browser's worker)
				public static function of(id:Int):$self {
					var c = helder.jobs.ChannelBase.find(id);
					return c != null ? cast c : new $path(id);
				}
			};
			td.pack = path.pack;
			td.pos = pos;
			Context.defineType(td);
		}
		return TPath({pack: ["helder", "jobs", "gen"], name: name});
	}
}

private enum Kind {
	IntK;
	FloatK;
	BoolK;
	Int64K;
	StringK;
	BytesK;
	BufferK;
	StructK(c:ClassType);
	ChannelK(c:ClassType);
	Nullable(t:Type);
	Under(t:Type, outer:Type);
	List(e:Type);
	Fields(fs:Array<{name:String, type:Type}>);
	Bad(why:String);
}
#end
