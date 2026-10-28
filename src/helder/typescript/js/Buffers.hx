package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;
import haxe.io.Bytes;
import haxe.io.FPHelper;

class JsBuffer extends JsObject {
    public var data:Bytes;
    public var maximum:Int;
    public var resizable:Bool;
    public function new(proto:JsObject,data:Bytes,maximum:Int,resizable:Bool){super(proto);this.data=data;this.maximum=maximum;this.resizable=resizable;}
    public inline function length():Int return data==null?0:data.length;
    override public function tag():String return "ArrayBuffer";
}
class JsDataView extends JsObject {
    public var buffer:JsBuffer;
    public var offset:Int;
    // -1 means a length-tracking view of a resizable buffer.
    public var size:Int;
    public function new(proto:JsObject,buffer:JsBuffer,offset:Int,size:Int){super(proto);this.buffer=buffer;this.offset=offset;this.size=size;}
    public function length():Int {
        if(buffer.data==null || offset>buffer.length() || size>=0 && offset+size>buffer.length())return error("TypeError","DataView is detached or out of bounds");
        return size<0?buffer.length()-offset:size;
    }
    override public function tag():String return "DataView";
}
@:access(helder.typescript.js.Builtins)
class Buffers {
    public static var BufferProto:JsObject;
    public static var ViewProto:JsObject;
    static var bufferCtor:JsFunction;
    // Native and WASI use the same finite host allocation limit.
    public static inline var MAX_BYTES=268435456;
    public static function toIndex(value:Dynamic):Float {
        var n=toIntegerOrInfinity(value);
        if(n<0 || n>9007199254740991.0)return error("RangeError","Index is outside the supported range");
        return n;
    }
    static function allocate(length:Float,maximum:Float,resizable:Bool,proto:JsObject):JsBuffer {
        if(length>maximum || length>MAX_BYTES || maximum>MAX_BYTES) return error("RangeError","ArrayBuffer allocation exceeds host limit");
        var data:Bytes;
        try data=Bytes.alloc(Std.int(length)) catch(_:Dynamic)return error("RangeError","ArrayBuffer allocation failed");
        return new JsBuffer(proto,data,Std.int(maximum),resizable);
    }
    public static function buffer(value:Dynamic):JsBuffer {
        if(!Std.isOfType(value,JsBuffer))return error("TypeError","Incompatible ArrayBuffer receiver");
        return value;
    }
    public static function detach(value:Dynamic):Dynamic {var b=buffer(value);b.data=null;return undef();}
    static function attached(b:JsBuffer):Void {if(b.data==null)error("TypeError","ArrayBuffer is detached");}
    static function view(value:Dynamic):JsDataView {
        if(!Std.isOfType(value,JsDataView))return error("TypeError","Incompatible DataView receiver");return value;
    }
    static function resize(b:JsBuffer,length:Dynamic):Dynamic {
        if(!b.resizable)return error("TypeError","ArrayBuffer is not resizable");
        var n=toIndex(length);attached(b);
        if(n>b.maximum)return error("RangeError","ArrayBuffer resize exceeds maximum");
        var result=allocate(n,b.maximum,true,BufferProto);
        var count=Std.int(Math.min(n,b.length()));if(count>0)result.data.blit(0,b.data,0,count);
        b.data=result.data;return undef();
    }
    static function transfer(b:JsBuffer,length:Dynamic,fixed:Bool):JsBuffer {
        var n=length==undef()?b.length():toIndex(length);attached(b);
        var resizable=b.resizable && !fixed;
        var result=allocate(n,resizable?b.maximum:n,resizable,BufferProto);
        var count=Std.int(Math.min(n,b.length()));if(count>0)result.data.blit(0,b.data,0,count);
        b.data=null;return result;
    }
    static function relative(value:Dynamic,length:Int):Int {
        var n=toIntegerOrInfinity(value);return Std.int(n<0?Math.max(length+n,0):Math.min(n,length));
    }
    static function slice(b:JsBuffer,start:Dynamic,end:Dynamic):JsBuffer {
        attached(b);var len=b.length(),first=relative(start,len),last=end==undef()?len:relative(end,len),count=Std.int(Math.max(last-first,0));
        var ctor=get(b,"constructor"),species:Dynamic=bufferCtor;
        if(ctor!=undef()) {
            if(!isObject(ctor))return error("TypeError","ArrayBuffer constructor must be an object");
            var candidate=get(ctor,"\x00@@species");
            if(candidate!=null && candidate!=undef())species=candidate;
        }
        if(!isConstructor(species))return error("TypeError","ArrayBuffer species must be a constructor");
        var result=buffer(construct(species,[count],species));attached(result);
        if(result==b || result.length()<count)return error("TypeError","Invalid ArrayBuffer species result");
        attached(b);var copy=Std.int(Math.min(count,b.length()-first));
        if(copy>0)result.data.blit(0,b.data,first,copy);
        return result;
    }
    public static function setup():Void {
        BufferProto=new JsObject(Builtins.ObjectProto);ViewProto=new JsObject(Builtins.ObjectProto);
        bufferCtor=Builtins.constructor("ArrayBuffer",1,BufferProto,(_,a,nt)->{
            if(nt==undef())return error("TypeError","ArrayBuffer requires new");
            var length=toIndex(arg(a,0)),maximum=length,resizable=false,options=arg(a,1);
            if(isObject(options)){var max=get(options,"maxByteLength");if(max!=undef()){maximum=toIndex(max);resizable=true;}}
            if(length>maximum)return error("RangeError","ArrayBuffer length exceeds maximum");
            return allocate(length,maximum,resizable,protoFrom(nt,BufferProto));
        });
        Builtins.method(bufferCtor,"isView",1,(_,a,_)->Std.isOfType(arg(a,0),JsDataView));
        Builtins.getter(bufferCtor,"\x00@@species",t->t);
        Builtins.getter(BufferProto,"byteLength",t->buffer(t).length());
        Builtins.getter(BufferProto,"maxByteLength",t->{var b=buffer(t);return b.data==null?0:b.maximum;});
        Builtins.getter(BufferProto,"resizable",t->buffer(t).resizable);
        Builtins.getter(BufferProto,"detached",t->buffer(t).data==null);
        Builtins.method(BufferProto,"resize",1,(t,a,_)->resize(buffer(t),arg(a,0)));
        Builtins.method(BufferProto,"slice",2,(t,a,_)->slice(buffer(t),arg(a,0),arg(a,1)));
        Builtins.method(BufferProto,"transfer",0,(t,a,_)->transfer(buffer(t),arg(a,0),false));
        Builtins.method(BufferProto,"transferToFixedLength",0,(t,a,_)->transfer(buffer(t),arg(a,0),true));
        BufferProto.setOwn(Symbols.toStringTag,"ArrayBuffer",Attr.HIDDEN|Attr.READONLY);
        Builtins.constructor("DataView",1,ViewProto,(_,a,nt)->{
            if(nt==undef())return error("TypeError","DataView requires new");
            var b=buffer(arg(a,0)),offset=toIndex(arg(a,1));attached(b);
            if(offset>b.length())return error("RangeError","DataView offset is out of bounds");
            var length=arg(a,2),size=length==undef()?(b.resizable?-1:b.length()-offset):toIndex(length);
            if(size>=0 && offset+size>b.length())return error("RangeError","DataView length is out of bounds");
            var proto=protoFrom(nt,ViewProto);attached(b);
            if(offset>b.length() || length!=undef() && offset+size>b.length())return error("RangeError","DataView is out of bounds");
            return new JsDataView(proto,b,Std.int(offset),Std.int(size));
        });
        var global:JsObject=Builtins.globals.get("globalThis");for(name in ["ArrayBuffer","DataView"])global.setOwn(name,Builtins.globals.get(name),Attr.HIDDEN);
        Builtins.getter(ViewProto,"buffer",t->view(t).buffer);
        Builtins.getter(ViewProto,"byteLength",t->view(t).length());
        Builtins.getter(ViewProto,"byteOffset",t->{var v=view(t);v.length();return v.offset;});
        ViewProto.setOwn(Symbols.toStringTag,"DataView",Attr.HIDDEN|Attr.READONLY);
        for(kind in ["Int8","Uint8","Int16","Uint16","Int32","Uint32","Float16","Float32","Float64"]) {
            Builtins.method(ViewProto,"get"+kind,1,(t,a,_)->{
                var v=view(t),index=toIndex(arg(a,0)),little=Seed.truth(arg(a,1)),length=v.length(),bytes=width(kind);
                if(index+bytes>length)return error("RangeError","DataView access is out of bounds");
                return read(v.buffer.data,v.offset+Std.int(index),kind,little);
            });
            Builtins.method(ViewProto,"set"+kind,2,(t,a,_)->{
                var v=view(t),index=toIndex(arg(a,0)),number=Seed.numeric(arg(a,1)),little=Seed.truth(arg(a,2)),length=v.length(),bytes=width(kind);
                if(index+bytes>length)return error("RangeError","DataView access is out of bounds");
                write(v.buffer.data,v.offset+Std.int(index),kind,little,number);return undef();
            });
        }
    }
    public static function width(kind:String):Int return switch(kind){case "Int8","Uint8","Uint8Clamped":1;case "Int16","Uint16","Float16":2;case "Int32","Uint32","Float32":4;default:8;};
    static function word(data:Bytes,index:Int,count:Int,little:Bool):Int {
        var result=0;for(i in 0...count)result|=data.get(index+(little?i:count-i-1))<<(i*8);return result;
    }
    static function putWord(data:Bytes,index:Int,count:Int,little:Bool,value:Int):Void {
        for(i in 0...count)data.set(index+(little?i:count-i-1),(value>>>(i*8))&255);
    }
    public static function read(data:Bytes,index:Int,kind:String,little:Bool):Float {
        var n=width(kind);
        if(kind=="Float64")return FPHelper.i64ToDouble(word(data,index+(little?0:4),4,little),word(data,index+(little?4:0),4,little));
        var bits=word(data,index,n,little);
        return switch(kind) {
            case "Int8":bits>=128?bits-256:bits;
            case "Int16":bits>=32768?bits-65536:bits;
            case "Int32":bits;
            case "Uint32":bits<0?bits+4294967296.0:bits;
            case "Float32":FPHelper.i32ToFloat(bits);
            case "Float16":halfValue(bits);
            default:bits;
        };
    }
    public static function write(data:Bytes,index:Int,kind:String,little:Bool,value:Float):Void {
        if(kind=="Float64") {
            var bits=FPHelper.doubleToI64(value);putWord(data,index+(little?0:4),4,little,bits.low);putWord(data,index+(little?4:0),4,little,bits.high);return;
        }
        var bits=kind=="Float32"?FPHelper.floatToI32(value):kind=="Float16"?halfBits(value):toInt32(value);
        putWord(data,index,width(kind),little,bits);
    }
    public static function halfValue(bits:Int):Float {
        var exponent=(bits>>10)&31,fraction=bits&1023;
        var value=exponent==31?(fraction==0?Math.POSITIVE_INFINITY:Math.NaN):exponent==0?fraction*Math.pow(2,-24):(1024+fraction)*Math.pow(2,exponent-25);
        return bits&32768!=0?-value:value;
    }
    public static function halfBits(value:Float):Int {
        value=Numbers.half(value);var bits=FPHelper.floatToI32(value),sign=(bits>>>16)&32768,exponent=(bits>>>23)&255,fraction=bits&8388607;
        if(exponent==255)return sign|31744|(fraction==0?0:512);
        if(exponent==0)return sign;
        if(exponent<113)return sign|Std.int(Math.abs(value)*16777216);
        return sign|((exponent-112)<<10)|(fraction>>>13);
    }
}
