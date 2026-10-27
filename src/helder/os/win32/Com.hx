package helder.os.win32;

#if macro
// The build macro of COM interfaces (helder.os.audio.Wasapi and
// helder.gfx's Direct3D 11): helder.os.VTable's, each function declared without
// a body and with @:slot(n) the method at index n of the interface's vtable
// (the order of the official headers' C vtables, the base interfaces'
// methods first), its first argument the object.
class Com {
	public static function build():Array<haxe.macro.Expr.Field>
		return helder.os.VTable.build();
}
#else
import hxmc.unsafe.*;

class Com {
	// the method at a slot of a COM object's vtable
	public static inline function method(self:Ptr, slot:Int):Ptr
		return helder.os.VTable.method(self, slot);

	// IUnknown::Release, when there is an object
	public static inline function release(o:Ptr)
		if (!o.isNull()) IUnknown.Release(o);

	// a GUID in native memory, kept for the process, as the headers write it
	public static function guid(d1:Int, d2:Int, d3:Int, d4:Array<Int>):Ptr {
		var p:Ptr<UInt8> = LibC.malloc(16), d:Ptr<Int32> = p.raw(), w:Ptr<UInt16> = p.raw();
		d.value = d1;
		w[2] = d2;
		w[3] = d3;
		for (i in 0...8)
			p[8 + i] = d4[i];
		return p;
	}
}

@:build(helder.os.win32.Com.build())
class IUnknown {
	@:slot(0) static function QueryInterface(self:Ptr, iid:Ptr, out:Ptr<Ptr>):Int;
	@:slot(1) static function AddRef(self:Ptr):Int;
	@:slot(2) static function Release(self:Ptr):Int;
}
#end
