package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

private typedef SetRecord={object:Dynamic,size:Float,has:Dynamic,keys:Dynamic};
private typedef Cursor={object:Dynamic,next:Dynamic};

// Set algebra uses the set-like protocol, rather than requiring another Set.
@:access(helder.typescript.js.Builtins)
class Sets {
    public static function setup():Void {
        for(name in ["union","intersection","difference","symmetricDifference","isSubsetOf","isSupersetOf","isDisjointFrom"])
            Builtins.SetProto.setOwn(name,Builtins.nativeFunction(name,1,(t,a,_)->run(name,t,arg(a,0))),Attr.HIDDEN);
    }
    static function size(m:JsMap):Int {var n=0;for(active in m.active)if(active)n++;return n;}
    static function contains(m:JsMap,v:Dynamic):Bool return Builtins.mapIndex(m,v)>=0;
    static function add(m:JsMap,v:Dynamic):Void {Builtins.mapPut(m,v,v);}
    static function copy(m:JsMap):JsMap {
        var out=new JsMap(Builtins.SetProto,true);
        for(i in 0...m.keys.length)if(m.active[i])add(out,m.keys[i]);
        return out;
    }
    static function record(o:Dynamic):SetRecord {
        if(!isObject(o))return error("TypeError","Set argument must be an object");
        var n=Seed.numeric(get(o,"size"));
        if(Math.isNaN(n))return error("TypeError","Set-like size is NaN");
        n=toIntegerOrInfinity(n);
        if(n<0)return error("RangeError","Set-like size is negative");
        var has=get(o,"has");if(!isCallable(has))return error("TypeError","Set-like has must be callable");
        var keys=get(o,"keys");if(!isCallable(keys))return error("TypeError","Set-like keys must be callable");
        return {object:o,size:n,has:has,keys:keys};
    }
    static function cursor(r:SetRecord):Cursor {
        var it=call(r.keys,r.object,[]);
        if(!isObject(it))return error("TypeError","Set-like keys must return an iterator object");
        return {object:it,next:get(it,"next")};
    }
    static function step(c:Cursor):Dynamic {
        var result=call(c.next,c.object,[]);
        if(!isObject(result))return error("TypeError","Iterator result must be an object");
        return Seed.truth(get(result,"done"))?finished:get(result,"value");
    }
    static function close(c:Cursor):Void {
        var fn=get(c.object,"return");if(fn==null || fn==undef())return;
        var result=call(fn,c.object,[]);
        if(!isObject(result))error("TypeError","Iterator return must return an object");
    }
    static function run(name:String,t:Dynamic,other:Dynamic):Dynamic {
        var m=Builtins.thisMap(t,true,name), r=record(other);
        if(name=="isSubsetOf" && size(m)>r.size)return false;
        if(name=="isSupersetOf" && size(m)<r.size)return false;
        if(name=="difference") {
            var out=copy(m);
            if(size(m)<=r.size){for(i in 0...out.keys.length)if(out.active[i] && Seed.truth(call(r.has,r.object,[out.keys[i]])))Builtins.mapDelete(out,out.keys[i]);}
            else {var it=cursor(r);while(true){var v=step(it);if(v==finished)break;Builtins.mapDelete(out,v);}}
            return out;
        }
        if(name=="isSubsetOf" || (name=="intersection" || name=="isDisjointFrom") && size(m)<=r.size) {
            var out=new JsMap(Builtins.SetProto,true),i=0;
            while(i<m.keys.length) {
                var at=i++;if(!m.active[at])continue;
                var value=m.keys[at],has=Seed.truth(call(r.has,r.object,[value]));
                if(name=="isSubsetOf" && !has)return false;
                if(name=="isDisjointFrom" && has)return false;
                if(name=="intersection" && has)add(out,value);
            }
            return name=="intersection"?(out:Dynamic):true;
        }
        var it=cursor(r);
        // Calling keys() can mutate the receiver; copy only after it returns.
        var out=name=="union" || name=="symmetricDifference"?copy(m):new JsMap(Builtins.SetProto,true);
        while(true) {
            var value=step(it);if(value==finished)break;
            var has=contains(m,value);
            switch(name) {
                case "union":add(out,value);
                case "intersection":if(has)add(out,value);
                case "symmetricDifference":if(has)Builtins.mapDelete(out,value);else if(!contains(out,value))add(out,value);
                case "isSupersetOf":if(!has){close(it);return false;}
                case "isDisjointFrom":if(has){close(it);return false;}
            }
        }
        return name=="isSupersetOf" || name=="isDisjointFrom"?true:(out:Dynamic);
    }
}
