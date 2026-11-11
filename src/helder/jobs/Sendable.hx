package helder.jobs;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

import helder.jobs.JobDefinition;

using haxe.macro.TypeTools;

// What can be sent to another thread or a browser's worker (as Swift's
// Sendable): a GC job's argument and result, a Channel's values. Checked
// at compile time (the culprit named, with where it is in the type: the
// check is JobDefinition's, the same for TypeScript's jobs; Haxe's types
// described to it here), and each one's codec generated (Wire):
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
	// ---- the check (JobDefinition's)

	// why t cannot be sent (where in t, and what), or null
	public static function reason(t:Type):Null<String>
		return JobDefinition.reason(sendType(t));

	// t as the check takes it
	public static function sendType(t:Type):SendType
		return new SendType(TypeTools.toString(t), () -> switch kind(t) {
			case IntK: SInt;
			case FloatK: SFloat;
			case BoolK: SBool;
			case Int64K: SInt64;
			case StringK: SString;
			case BytesK: SBytes;
			case BufferK: SBuffer;
			case StructK(_): SStruct;
			case ChannelK(_): SChannel;
			case Nullable(i): SNull(sendType(i));
			case Under(i, _): SUnder(sendType(i));
			case List(e): SList(sendType(e));
			case Fields(fs): SFields([for (f in fs) {name: f.name, type: sendType(f.type)}]);
			case Bad(m): SBad(m);
		});

	static function check(t:Type, what:String, pos:Position) {
		var r = reason(t);
		if (r != null) Context.error(JobDefinition.message(what, r), pos);
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

	// ---- job(f)

	// job(f) (Jobs.job, a definition: src/helder/compiler/DESIGN.md 4): f a
	// static or module-level function named (the argument's kernel tree a
	// reference to it), checked as its tier wants, and a class of its own
	// beside it, <Class>_<f>_Job: its worker entry (a GC job's: a callback,
	// its input read and its result written) and run(input), a coroutine;
	// the value is its one instance.
	public static function definition(f:Expr):Expr {
		var a = new JobAdapter(f);
		// (static: a function named, checked by the kernel's adapter; its
		// input and result Sendable, checked by the handler)
		var free = new JobDefinition().generate(a.node(f), a).gcFree;
		var c = a.c, cf = a.cf, args = a.args, ret = a.ret;
		var fpath = field(classExpr(c), cf.name);
		var module = c.module, pack = module.split(".");
		pack.pop();
		var name = (StringTools.endsWith(c.name, "_Fields_") ? module.split(".").pop() : c.name) + "_" + cf.name + "_Job";
		var path = pack.concat([name]).join(".");
		var tp:TypePath = {pack: pack, name: name};
		var exists = try Context.getType(path) != null catch (_:Dynamic) false;
		if (exists) return macro $p{pack.concat([name, "instance"])};
		var fields:Array<Field>;
		if (free) {
			fields = (macro class {
				// (no input: none)
				@:coroutine public function run(?input:hxmc.unsafe.IoBuffer):hxmc.unsafe.IoBuffer
					return helder.jobs.Jobs.runFree(hxmc.unsafe.Callback.addr($fpath), input ?? cast hxmc.unsafe.Ptr.nil());
			}).fields;
		} else {
			var void = isVoid(ret);
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
			var entry = macro $p{pack.concat([name, "entry"])};
			var i = args.length == 1 ? macro {
				var w = new helder.jobs.Wire.Writer();
				${write(args[0].t, macro w, macro input)};
				w.done();
			} : macro cast hxmc.unsafe.Ptr.nil();
			var it = args.length == 1 ? TypeTools.toComplexType(args[0].t) : null;
			var rt = TypeTools.toComplexType(ret);
			var run:Expr = void ? macro helder.jobs.Jobs.runGcVoid(hxmc.unsafe.Callback.addr($entry), $i) : macro {
				var out = helder.jobs.Jobs.runGc(hxmc.unsafe.Callback.addr($entry), $i);
				var r = new helder.jobs.Wire.Reader(out);
				var v:$rt = ${read(ret, macro r)};
				helder.jobs.Jobs.free(out);
				return v;
			};
			var runField:Field = {
				name: "run",
				access: [APublic],
				meta: [{name: ":coroutine", pos: f.pos}],
				kind: FFun({args: it == null ? [] : [{name: "input", type: it}], ret: rt, expr: run}),
				pos: f.pos
			};
			fields = (macro class {
				@:hxmc.callback public static function entry(p:hxmc.unsafe.Ptr):Int {
					var job:helder.jobs.JobRecord = cast p;
					return try {
						$head;
						$body;
					} catch (e:Dynamic) helder.jobs.Jobs.failed(job, e);
				}
			}).fields.concat([runField]);
		}
		var td = macro class $name {
			public static final instance = new $tp();

			function new() {}
		};
		td.fields = td.fields.concat(fields);
		td.pack = pack;
		td.pos = f.pos;
		// (helder.jobs' internals, and the job's function: private too)
		var owner = c.pack.concat([c.name]).join(".");
		td.meta = [
			{name: ":noCompletion", pos: f.pos},
			{name: ":access", params: [macro helder.jobs], pos: f.pos},
			{name: ":access", params: [Context.parse(owner, f.pos)], pos: f.pos}
		];
		Context.defineType(td, module);
		return macro $p{pack.concat([name, "instance"])};
	}

	static function isVoid(t:Type):Bool
		return switch Context.follow(t) {
			case TAbstract(_.get() => {name: "Void", pack: []}, _): true;
			case _: false;
		}

	// ---- Channel<T>: a class per value type (helder.jobs.gen.Channel_<hash>)

	static function defined(name:String):Bool
		return try Context.getType("helder.jobs.gen." + name) != null catch (_:Dynamic) false;

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

// job(f)'s Haxe adapter: f the static or module-level function named, its
// signature from its type (a GC-free job's: a kernel, which hxmc checks)
private class JobAdapter extends helder.definition.HaxeAdapter implements helder.jobs.JobDefinition.JobAdapter {
	public var c:ClassType;
	public var cf:ClassField;
	public var args:Array<{name:String, opt:Bool, t:Type}>;
	public var ret:Type;

	final f:Expr;

	public function new(f:Expr) {
		super("job");
		this.f = f;
	}

	public function signature(_):JobSignature {
		var typed = Context.typeExpr(f);
		switch typed.expr {
			case TField(_, FStatic(cr, fr)):
				c = cr.get();
				cf = fr.get();
			case _:
				return error("a job is a static or module-level function, named (Class.field, field)", f.pos);
		}
		if (cf.params.length > 0) error('${cf.name} has type parameters (its values\' types must be known)', f.pos);
		switch Context.follow(cf.type) {
			case TFun(x, r):
				args = x;
				ret = r;
			case _:
				return error("a job is a function", f.pos);
		}
		// (GC-free: it takes a Job, which only the pool hands out)
		var free = args.length == 1 && switch args[0].t {
			case TAbstract(_.get() => {name: "Job", pack: ["helder", "jobs"]}, _): true;
			case _: false;
		}
		if (free && (!cf.meta.has(":hxmc.kernel") || !cf.meta.has(":hxmc.callback") || !Context.unify(ret, Context.getType("Int"))))
			error('a GC-free job is an @:hxmc.kernel @:hxmc.callback static function (job:helder.jobs.Job):Int (${cf.name})', f.pos);
		@:privateAccess var void = Sendable.isVoid(ret);
		return {
			name: cf.name,
			inputs: [for (a in args) Sendable.sendType(a.t)],
			result: void ? null : Sendable.sendType(ret),
			captures: [],
			gcFree: free
		};
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
