package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

class IteratorRecord {
    public var target:Dynamic;
    public var next:Dynamic;
    public var done=false;
    public function new(target:Dynamic,next:Dynamic){this.target=target;this.next=next;}
}
class JsIteratorWrapper extends JsObject {
    public var record:IteratorRecord;
    public function new(proto:JsObject,record:IteratorRecord){super(proto);this.record=record;}
}
class JsIteratorHelper extends JsObject {
    public var outer:IteratorRecord;
    public var inner:IteratorRecord=null;
    public var kind:String;
    public var callback:Dynamic;
    public var counter:Float=0;
    public var remaining:Float;
    public var busy=false;
    public var completed=false;
    public function new(proto:JsObject,record:IteratorRecord,kind:String,callback:Dynamic,remaining:Float){super(proto);this.outer=record;this.kind=kind;this.callback=callback;this.remaining=remaining;}
}
@:access(helder.typescript.js.Builtins)
class Iterators {
    static var HelperProto:JsObject;
    static var WrapperProto:JsObject;
    static var constructor:JsFunction;
    static function require(value:Dynamic):Void {if(!isObject(value))error("TypeError","Iterator receiver must be an object");}
    static function direct(target:Dynamic):IteratorRecord {require(target);return new IteratorRecord(target,get(target,"next"));}
    static function flatten(value:Dynamic,strings:Bool):IteratorRecord {
        if(!isObject(value) && !(strings && Std.isOfType(value,String)))return error("TypeError","Expected an iterable or iterator object");
        var method=get(value,Symbols.iterator),iterator=value;
        if(method!=null && method!=undef())iterator=call(method,value,[]);
        return direct(iterator);
    }
    static function result(value:Dynamic,done:Bool):Dynamic return object(["value","done"],[value,done]);
    static function step(record:IteratorRecord):Dynamic {
        if(record.done)return finished;
        try {
            var next=call(record.next,record.target,[]);require(next);
            if(Seed.truth(get(next,"done"))){record.done=true;return finished;}
            return get(next,"value");
        } catch(e:Dynamic){record.done=true;throw e;}
    }
    static function close(record:IteratorRecord):Void {
        if(record.done)return;record.done=true;
        var method=get(record.target,"return");
        if(method!=null && method!=undef())require(call(method,record.target,[]));
    }
    static function closeThrow(record:IteratorRecord,error:Dynamic):Dynamic {try close(record) catch(_:Dynamic){}throw error;}
    static function callbackRecord(target:Dynamic,callback:Dynamic):IteratorRecord {
        require(target);if(!isCallable(callback))return closeThrow(new IteratorRecord(target,undef()),Builtins.makeError("TypeError","Iterator callback must be callable"));
        return direct(target);
    }
    static function limited(target:Dynamic,value:Dynamic,kind:String):JsIteratorHelper {
        require(target);var record=new IteratorRecord(target,undef()),n:Float;
        try {n=Seed.numeric(value);if(Math.isNaN(n) || Math.isFinite(n) && n>9007199254740991.0)error("RangeError","Iterator limit is outside the supported range");n=toIntegerOrInfinity(n);if(n<0)error("RangeError","Iterator limit cannot be negative");}
        catch(e:Dynamic)return closeThrow(record,e);
        record.next=get(target,"next");return new JsIteratorHelper(HelperProto,record,kind,undef(),n);
    }
    static function helper(value:Dynamic):JsIteratorHelper {if(!Std.isOfType(value,JsIteratorHelper))return error("TypeError","Incompatible Iterator Helper receiver");return value;}
    static function helperNext(h:JsIteratorHelper):Dynamic {
        if(h.busy)return error("TypeError","Iterator Helper is already running");
        if(h.completed)return result(undef(),true);
        h.busy=true;
        try {
            while(true) {
                if(h.kind=="take" && h.remaining==0){h.completed=true;close(h.outer);h.busy=false;return result(undef(),true);}
                if(h.kind=="drop")while(h.remaining>0){h.remaining--;if(step(h.outer)==finished){h.completed=true;h.busy=false;return result(undef(),true);}}
                if(h.kind=="flatMap" && h.inner!=null){
                    var innerValue:Dynamic;
                    try innerValue=step(h.inner) catch(e:Dynamic){closeThrow(h.outer,e);return null;}
                    if(innerValue!=finished){h.busy=false;return result(innerValue,false);}h.inner=null;
                }
                var value=step(h.outer);
                if(value==finished){h.completed=true;h.busy=false;return result(undef(),true);}
                if(h.kind=="take")h.remaining--;
                if(h.kind=="map" || h.kind=="filter" || h.kind=="flatMap") {
                    var mapped:Dynamic;
                    try mapped=call(h.callback,undef(),[value,h.counter++]) catch(e:Dynamic){closeThrow(h.outer,e);return null;}
                    if(h.kind=="map")value=mapped;
                    else if(h.kind=="filter"){if(!Seed.truth(mapped))continue;}
                    else {try h.inner=flatten(mapped,false) catch(e:Dynamic){closeThrow(h.outer,e);}continue;}
                }
                h.busy=false;return result(value,false);
            }
        } catch(e:Dynamic){h.completed=true;h.busy=false;throw e;}
    }
    static function helperReturn(h:JsIteratorHelper):Dynamic {
        if(h.busy)return error("TypeError","Iterator Helper is already running");
        if(h.completed)return result(undef(),true);
        h.busy=true;h.completed=true;
        try {
            if(h.inner!=null)try close(h.inner) catch(e:Dynamic){closeThrow(h.outer,e);}
            close(h.outer);h.busy=false;return result(undef(),true);
        } catch(e:Dynamic){h.busy=false;throw e;}
    }
    static function terminal(target:Dynamic,fn:Dynamic,kind:String):Dynamic {
        var record=kind=="toArray"?direct(target):callbackRecord(target,fn),counter:Float=0,values:Array<Dynamic>=[];
        while(true){
            var value=step(record);
            if(value==finished)return kind=="toArray"?array(values):kind=="some"?false:kind=="every"?true:undef();
            if(kind=="toArray"){values.push(value);continue;}
            var mapped:Dynamic;
            try mapped=call(fn,undef(),[value,counter++]) catch(e:Dynamic)return closeThrow(record,e);
            if(kind=="some" && Seed.truth(mapped) || kind=="every" && !Seed.truth(mapped) || kind=="find" && Seed.truth(mapped)){
                close(record);return kind=="find"?value:kind=="some";
            }
        }
    }
    static function reduce(target:Dynamic,args:Array<Dynamic>):Dynamic {
        var record=callbackRecord(target,arg(args,0)),fn=arg(args,0),counter:Float=0,accumulator:Dynamic;
        if(args.length>1)accumulator=args[1];else{accumulator=step(record);if(accumulator==finished)return error("TypeError","Reduce of empty iterator without initial value");counter=1;}
        while(true){var value=step(record);if(value==finished)return accumulator;try accumulator=call(fn,undef(),[accumulator,value,counter++]) catch(e:Dynamic)return closeThrow(record,e);}
    }
    static function inheritedAccessor(proto:JsObject,key:String,value:Dynamic):Void {
        var name=Symbols.functionName(key);
        proto.setOwn(key,new Accessor(Builtins.nativeFunction("get "+name,0,(_,_,_)->value),Builtins.nativeFunction("set "+name,1,(t,a,_)->{
            require(t);if(t==proto)return error("TypeError","Cannot set an intrinsic Iterator prototype property");
            if(hasOwnKey(t,key))put(t,key,arg(a,0));else Builtins.defineProperty(t,key,object(["value","writable","enumerable","configurable"],[arg(a,0),true,true,true]));
            return undef();
        })),Attr.HIDDEN);
    }
    public static function setup():Void {
        var proto=Builtins.IteratorProto;
        HelperProto=new JsObject(proto);WrapperProto=new JsObject(proto);
        constructor=Builtins.constructor("Iterator",0,proto,(_,_,nt)->{if(nt==undef() || nt==constructor)return error("TypeError","Iterator is an abstract constructor");return new JsObject(protoFrom(nt,proto));});
        inheritedAccessor(proto,"constructor",constructor);inheritedAccessor(proto,Symbols.toStringTag,"Iterator");
        Builtins.method(constructor,"from",1,(_,a,_)->{
            var record=flatten(arg(a,0),true),p:JsObject=(cast record.target:JsObject).proto;
            while(p!=null){if(p==proto)return record.target;p=p.proto;}
            return new JsIteratorWrapper(WrapperProto,record);
        });
        Builtins.method(WrapperProto,"next",0,(t,_,_)->{
            if(!Std.isOfType(t,JsIteratorWrapper))return error("TypeError","Incompatible Iterator wrapper receiver");var r=(t:JsIteratorWrapper).record;return call(r.next,r.target,[]);
        });
        Builtins.method(WrapperProto,"return",0,(t,_,_)->{
            if(!Std.isOfType(t,JsIteratorWrapper))return error("TypeError","Incompatible Iterator wrapper receiver");var r=(t:JsIteratorWrapper).record,method=get(r.target,"return");
            return method==null || method==undef()?result(undef(),true):call(method,r.target,[]);
        });
        Builtins.method(HelperProto,"next",0,(t,_,_)->helperNext(helper(t)));
        Builtins.method(HelperProto,"return",0,(t,_,_)->helperReturn(helper(t)));
        HelperProto.setOwn(Symbols.toStringTag,"Iterator Helper",Attr.HIDDEN|Attr.READONLY);
        for(kind in ["map","filter","flatMap"])Builtins.method(proto,kind,1,(t,a,_)->new JsIteratorHelper(HelperProto,callbackRecord(t,arg(a,0)),kind,arg(a,0),0));
        for(kind in ["take","drop"])Builtins.method(proto,kind,1,(t,a,_)->limited(t,arg(a,0),kind));
        for(kind in ["some","every","find","forEach"])Builtins.method(proto,kind,1,(t,a,_)->terminal(t,arg(a,0),kind));
        Builtins.method(proto,"toArray",0,(t,_,_)->terminal(t,undef(),"toArray"));
        Builtins.method(proto,"reduce",1,(t,a,_)->reduce(t,a));
        Builtins.method(proto,"\x00@@dispose",0,(t,_,_)->{var method=get(t,"return");if(method!=null && method!=undef())call(method,t,[]);return undef();});
        (cast Builtins.globals.get("globalThis"):JsObject).setOwn("Iterator",constructor,Attr.HIDDEN);
    }
}
