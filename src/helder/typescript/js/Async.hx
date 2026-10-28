package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

// Generator objects: a compiled step function (see Frontend.resumableClosure)
// resumed with a value and a mode (0 next, 1 throw, 2 return).
class JsGenerator extends JsObject {
    public var step:Dynamic;
    public var state=0;
    public var started=false;
    public var running=false;
    public var finished=false;
    public var suspended=false;
    public var frame:Array<Dynamic>=null;
    // (the last suspension was an await, not a yield)
    public var awaiting=false;
    public function new(proto:JsObject,step:Dynamic) {super(proto);this.step=step;}
    override public function tag():String return "Generator";
}
class Async {
    public static var GeneratorProto:JsObject;
    public static function setup():Void {
        GeneratorProto=new JsObject(Builtins.IteratorProto);
        for(name in ["next","throw","return"]) {
            var mode=name=="next"?0:name=="throw"?1:2;
            GeneratorProto.setOwn(name,Builtins.nativeFunction(name,1,(t,a,_)->{
                if(!Std.isOfType(t,JsGenerator))error("TypeError",name+" method called on incompatible receiver "+Seed.text(t));
                return resume(t,arg(a,0),mode);
            }),Attr.HIDDEN);
        }
        GeneratorProto.setOwn(Symbols.toStringTag,"Generator",Attr.HIDDEN|Attr.READONLY);
    }
    public static function generator(step:Dynamic):Dynamic return new JsGenerator(GeneratorProto,step);
    // One step: the result object of next/throw/return.
    public static function resume(g:JsGenerator,sent:Dynamic,mode:Int):Dynamic {
        if(g.running)error("TypeError","Generator is already running");
        if(!g.started && mode!=0)g.finished=true;
        if(g.finished) {
            if(mode==1)throw sent;
            return object(["value","done"],[mode==2?sent:undef(),true]);
        }
        g.started=true;g.running=true;g.suspended=false;
        var v:Dynamic;
        try v=call(g.step,undef(),[g,sent,mode])
        catch(e:Dynamic){g.running=false;g.finished=true;throw e;}
        g.running=false;
        if(!g.suspended){g.finished=true;g.frame=null;}
        return object(["value","done"],[v,!g.suspended]);
    }
    public static function suspend(g:JsGenerator,id:Int,kind:Int):Void {g.state=id;g.suspended=true;g.awaiting=kind==1;}
    // yield*: forward a resumption to the inner iterator; its result object.
    public static function delegate(it:Dynamic,received:Dynamic,mode:Dynamic):Dynamic {
        var m=Std.int(Seed.numeric(mode));
        if(m==0)return Std.isOfType(it,JsIterator)?Builtins.iteratorNext(it):checked(callMethod(it,"next",[received]));
        var name=m==1?"throw":"return";
        var f=get(it,name);
        if(f==null || f==undef()) {
            if(m==2)return object(["value","done"],[received,true]);
            var close=get(it,"return");if(close!=null && close!=undef())call(close,it,[]);
            return error("TypeError","The iterator does not provide a 'throw' method");
        }
        return checked(call(f,it,[received]));
    }
    static function checked(r:Dynamic):Dynamic {if(!isObject(r))error("TypeError","Iterator result "+Seed.text(r)+" is not an object");return r;}
}
