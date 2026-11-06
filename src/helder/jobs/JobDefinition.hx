package helder.jobs;

import helder.definition.Kernel;

// job(f)'s handler (src/helder/compiler/DESIGN.md 4), the same for both
// languages (Haxe's Jobs.job: Sendable; TypeScript's helder/jobs:
// helder.typescript.lower's Definitions): f's input, result and the
// module-level constants it reads (TypeScript's: a worker's instance has
// its own module, they are copied in) checked Sendable, each adapter
// describing its language's types as SendTypes. What can be sent:
//
//   Int, Float, Bool, haxe.Int64 (number, boolean)          copied
//   String, haxe.io.Bytes (string, Uint8Array)               copied (null too)
//   hxmc.unsafe.IoBuffer                                     moved
//   @:hxmc.struct classes                                    copied (their bytes)
//   Null<T> (T | null, T | undefined), abstracts over a T    as T
//   { a:T, ... }, Array<T>                                   copied, field by field, element by element
//   Channel<T>                                               the channel itself
//
// Not: classes and interfaces (shared mutable state), enums, functions,
// dynamic values, addresses, type parameters, maps, recursive types.
class JobDefinition implements Definition<JobAdapter, JobSignature> {
	public static inline var WHAT = "flat values, String, Bytes, IoBuffer, hxmc structs, and anonymous structures, Arrays and Channels of these";

	public final name = "job";

	public function new() {}

	public function generate(arg:KNode, a:JobAdapter):JobSignature {
		var s = a.signature(arg);
		if (s.gcFree) return s;
		if (s.inputs.length > 1) a.error('${s.name} takes ${s.inputs.length} arguments (a job takes one at most: an anonymous structure for more)', arg.pos);
		if (s.inputs.length == 1) check(s.inputs[0], '${s.name}\'s input', arg.pos, a);
		if (s.result != null) check(s.result, '${s.name}\'s result', arg.pos, a);
		for (c in s.captures)
			check(c.type, '${s.name}\'s constant ${c.name}', c.pos, a);
		return s;
	}

	static function check(t:SendType, what:String, pos:KPos, a:Adapter) {
		var r = reason(t);
		if (r != null) a.error(message(what, r), pos);
	}

	public static function message(what:String, reason:String):String
		return 'helder.jobs: $what cannot be sent: $reason (sendable: $WHAT)';

	// why t cannot be sent (where in t, and what), or null
	public static function reason(t:SendType):Null<String>
		return why(t, "", []);

	static function why(t:SendType, at:String, seen:Array<String>):Null<String> {
		var here = at == "" ? "" : at + ": ";
		return switch t.kind() {
			case SBad(m): here + t.text + " is " + m;
			case SNull(i) | SUnder(i): why(i, at, seen);
			case SList(e): why(e, at + "[]", seen);
			case SFields(fs):
				if (seen.contains(t.text)) return here + t.text + " is recursive";
				seen.push(t.text);
				for (f in fs) {
					var r = why(f.type, at + "." + f.name, seen);
					if (r != null) return r;
				}
				seen.pop();
				null;
			case _: null;
		}
	}
}

// What a job's adapter tells of its function: its name, its inputs' and
// result's types (null: Void), the constants it reads, whether it is a
// GC-free job (Haxe's @:hxmc.unsafe callback, which takes a Job: unchecked)
typedef JobSignature = {
	name:String,
	inputs:Array<SendType>,
	result:Null<SendType>,
	captures:Array<{name:String, type:SendType, pos:KPos}>,
	gcFree:Bool,
	// (the adapter's own: what it generates from)
	?source:Any
}

interface JobAdapter extends Adapter {
	// the job's function, the argument's node: its signature (errors at its position)
	function signature(f:KNode):JobSignature;
}

enum SendKind {
	SInt;
	SFloat;
	SBool;
	SInt64;
	SString;
	SBytes;
	SBuffer;
	SStruct;
	SChannel;
	SNull(t:SendType);
	SUnder(t:SendType);
	SList(e:SendType);
	SFields(fields:Array<{name:String, type:SendType}>);
	SBad(why:String);
}

// A type as an adapter describes it to the check: its text (as its
// language writes it) and what it is, made when asked (a recursive type's
// fields name it again)
class SendType {
	public final text:String;

	final make:() -> SendKind;
	var made:Null<SendKind> = null;

	public function new(text:String, make:() -> SendKind) {
		this.text = text;
		this.make = make;
	}

	public function kind():SendKind {
		if (made == null) made = make();
		return made;
	}
}
