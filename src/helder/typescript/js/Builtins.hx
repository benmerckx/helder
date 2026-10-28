package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;

// Built-in objects: prototypes, constructors and their methods.
class Builtins {
    public static var ObjectProto:JsObject;
    public static var FunctionProto:JsObject;
    public static var ArrayProto:JsObject;
    public static var StringProto:JsObject;
    public static var NumberProto:JsObject;
    public static var BooleanProto:JsObject;
    public static var SymbolProto:JsObject;
    public static var ErrorProto:JsObject;
    public static var IteratorProto:JsObject;
    public static var ArrayIteratorProto:JsObject;
    public static var MapIteratorProto:JsObject;
    public static var SetIteratorProto:JsObject;
    public static var StringIteratorProto:JsObject;
    public static var MapProto:JsObject;
    public static var SetProto:JsObject;
    public static var globals:Map<String,Dynamic>=null;
    public static var arrayIterationChanged=false;
    public static var boundTarget="\x00@target";
    static var errors:Map<String,JsFunction>=[];
    static var ready=false;
    static var asyncExpected=false;
    static var asyncDone=0;
    public static function checkAsyncTest():Void {if(asyncExpected && asyncDone!=1)error("Test262Error","$DONE was not called exactly once");}

    public static function nativeFunction(name:String,arity:Int,fn:(Dynamic,Array<Dynamic>,Dynamic)->Dynamic,constructor=false):JsFunction return native(name,arity,fn,constructor);
    static function native(name:String,arity:Int,fn:(Dynamic,Array<Dynamic>,Dynamic)->Dynamic,constructor=false):JsFunction {
        var f=new JsFunction(FunctionProto,constructor?JsFunction.PLAIN:JsFunction.METHOD,name,arity);f.native=fn;return f;
    }
    static function method(target:JsObject,name:String,arity:Int,fn:(Dynamic,Array<Dynamic>,Dynamic)->Dynamic):Void
        target.setOwn(name,native(Symbols.functionName(name),arity,fn),Attr.HIDDEN);
    static function getter(target:JsObject,name:String,fn:Dynamic->Dynamic):Void
        target.setOwn(name,new Accessor(native("get "+Symbols.functionName(name),0,(t,_,_)->fn(t)),null),Attr.HIDDEN);
    static function constant(target:JsObject,name:String,v:Dynamic):Void target.setOwn(name,v,Attr.HIDDEN|Attr.READONLY|Attr.LOCKED);
    static function constructor(name:String,arity:Int,proto:JsObject,fn:(Dynamic,Array<Dynamic>,Dynamic)->Dynamic):JsFunction {
        var c=native(name,arity,fn,true);
        c.setOwn("prototype",proto,Attr.HIDDEN|Attr.READONLY|Attr.LOCKED);proto.setOwn("constructor",c,Attr.HIDDEN);
        globals.set(name,c);return c;
    }
    static function callback(f:Dynamic):Dynamic {if(!isCallable(f))error("TypeError",Seed.text(f)+" is not a function");return f;}

    public static function init():Void {
        if(ready)return;ready=true;globals=[];
        ObjectProto=new JsObject(null);
        FunctionProto=new JsFunction(ObjectProto,JsFunction.METHOD,"",0);(cast FunctionProto:JsFunction).native=(_,_,_)->undef();
        ArrayProto=new JsArray(ObjectProto);
        StringProto=new JsObject(ObjectProto);NumberProto=new JsObject(ObjectProto);BooleanProto=new JsObject(ObjectProto);SymbolProto=new JsObject(ObjectProto);
        ErrorProto=new JsObject(ObjectProto);
        IteratorProto=new JsObject(ObjectProto);
        ArrayIteratorProto=new JsObject(IteratorProto);MapIteratorProto=new JsObject(IteratorProto);SetIteratorProto=new JsObject(IteratorProto);StringIteratorProto=new JsObject(IteratorProto);
        MapProto=new JsObject(ObjectProto);SetProto=new JsObject(ObjectProto);
        setupObject();setupFunction();setupArray();setupString();setupNumber();setupBoolean();setupSymbol();
        setupErrors();setupIterators();setupCollections();Sets.setup();setupGlobals();
        Numbers.setup();Json.setup();Async.setup();Promises.setup();AsyncArray.setup();Regex.setup();Dates.setup();Buffers.setup();Iterators.setup();RegexEscapes.setup();
        var global:JsObject=globals.get("globalThis");global.setOwn("Promise",globals.get("Promise"),Attr.HIDDEN);global.setOwn("JSON",globals.get("JSON"),Attr.HIDDEN);
    }
    public static function global(name:String):Dynamic {
        if(globals.exists(name))return globals.get(name);
        return error("ReferenceError",name+" is not defined");
    }

    // Object
    static function setupObject():Void {
        var o=ObjectProto;
        method(o,"hasOwnProperty",1,(t,a,_)->hasOwnKey(toObject(t),key(arg(a,0))));
        method(o,"isPrototypeOf",1,(t,a,_)->{var v=arg(a,0);if(!isObject(v))return false;var p=(v:JsObject).proto;while(p!=null){if(p==t)return true;p=p.proto;}return false;});
        method(o,"propertyIsEnumerable",1,(t,a,_)->{var obj=toObject(t);var k=key(arg(a,0));return hasOwnKey(obj,k) && obj.attr(k) & Attr.HIDDEN==0;});
        method(o,"toString",0,(t,_,_)->objectToString(t));
        method(o,"toLocaleString",0,(t,_,_)->callMethod(t,"toString",[]));
        method(o,"valueOf",0,(t,_,_)->toObject(t));
        o.setOwn("__proto__",new Accessor(native("get __proto__",0,(t,_,_)->{var p=toObject(t).proto;return p;}),native("set __proto__",1,(t,a,_)->{setPrototype(t,arg(a,0));return undef();})),Attr.HIDDEN);
        var c=constructor("Object",1,o,(t,a,nt)->{var v=arg(a,0);return v==null || v==undef()?new JsObject(ObjectProto):toObject(v);});
        method(c,"keys",1,(_,a,_)->array([for(k in keys(toObject(arg(a,0))))k]));
        method(c,"values",1,(_,a,_)->{var o=toObject(arg(a,0));return array([for(k in keys(o))get(o,k)]);});
        method(c,"entries",1,(_,a,_)->{var o=toObject(arg(a,0));return array([for(k in keys(o))array([k,get(o,k)])]);});
        method(c,"assign",2,(_,a,_)->{var target=toObject(arg(a,0));for(source in a.slice(1))if(source!=null && source!=undef()){var s=toObject(source);for(k in ownPropertyKeys(s))if(enumerableOwn(s,k))put(target,k,get(s,k));}return target;});
        method(c,"fromEntries",1,(_,a,_)->{var o=new JsObject(ObjectProto);for(entry in toList(arg(a,0)))defineOwn(o,key(get(entry,0)),get(entry,1));return o;});
        method(c,"hasOwn",2,(_,a,_)->hasOwnKey(toObject(arg(a,0)),key(arg(a,1))));
        method(c,"is",2,(_,a,_)->sameValue(arg(a,0),arg(a,1)));
        method(c,"getPrototypeOf",1,(_,a,_)->toObject(arg(a,0)).proto);
        method(c,"setPrototypeOf",2,(_,a,_)->{var o=arg(a,0);var p=arg(a,1);if(p!=null && !isObject(p))error("TypeError","Object prototype may only be an Object or null: "+Seed.text(p));setPrototype(o,p);return o;});
        method(c,"create",2,(_,a,_)->{var p=arg(a,0);if(p!=null && !isObject(p))error("TypeError","Object prototype may only be an Object or null: "+Seed.text(p));var o=new JsObject(p);if(arg(a,1)!=undef())defineProperties(o,arg(a,1));return o;});
        method(c,"defineProperty",3,(_,a,_)->{var o=arg(a,0);if(!isObject(o))error("TypeError","Object.defineProperty called on non-object");defineProperty(o,key(arg(a,1)),arg(a,2));return o;});
        method(c,"defineProperties",2,(_,a,_)->{var o=arg(a,0);if(!isObject(o))error("TypeError","Object.defineProperties called on non-object");defineProperties(o,arg(a,1));return o;});
        method(c,"getOwnPropertyNames",1,(_,a,_)->{var o=toObject(arg(a,0));var names:Array<Dynamic>=[for(k in ownPropertyKeys(o))if(!Symbols.isSymbolKey(k))k];return array(names);});
        method(c,"getOwnPropertySymbols",1,(_,a,_)->{var o=toObject(arg(a,0));var symbols:Array<Dynamic>=[for(k in ownPropertyKeys(o))if(Symbols.isSymbolKey(k) && Symbols.fromKey(k)!=null)Symbols.fromKey(k)];return array(symbols);});
        method(c,"getOwnPropertyDescriptor",2,(_,a,_)->descriptor(toObject(arg(a,0)),key(arg(a,1))));
        method(c,"getOwnPropertyDescriptors",1,(_,a,_)->{var o=toObject(arg(a,0));var r=new JsObject(ObjectProto);for(k in ownPropertyKeys(o))r.setOwn(k,descriptor(o,k));return r;});
        method(c,"freeze",1,(_,a,_)->{integrity(arg(a,0),true);return arg(a,0);});
        method(c,"seal",1,(_,a,_)->{integrity(arg(a,0),false);return arg(a,0);});
        method(c,"preventExtensions",1,(_,a,_)->{if(isObject(arg(a,0)))(arg(a,0):JsObject).extensible=false;return arg(a,0);});
        method(c,"isFrozen",1,(_,a,_)->testIntegrity(arg(a,0),true));
        method(c,"isSealed",1,(_,a,_)->testIntegrity(arg(a,0),false));
        method(c,"isExtensible",1,(_,a,_)->isObject(arg(a,0)) && (arg(a,0):JsObject).extensible);
        method(c,"groupBy",2,(_,a,_)->groupBy(arg(a,0),arg(a,1),false));
    }
    // GroupBy consumes one iterator value per callback and caches the next method.
    // Only callback/key failures close the iterator; iterator-step failures do not.
    static function groupBy(items:Dynamic,fn:Dynamic,isMap:Bool):Dynamic {
        if(items==null || items==undef())return error("TypeError","Grouping requires an iterable");
        var f=callback(fn),it=iterator(items),nextFn=get(it,"next");
        var result:JsObject=isMap?new JsMap(MapProto,false):new JsObject(null);
        var i:Float=0;
        while(true) {
            if(i>=9007199254740991.0)return groupCloseThrow(it,makeError("TypeError","Too many grouped values"));
            var step=call(nextFn,it,[]);
            if(!isObject(step))return error("TypeError","Iterator result must be an object");
            if(Seed.truth(get(step,"done")))return result;
            var value=get(step,"value"),k:Dynamic;
            try {k=call(f,undef(),[value,i]);if(!isMap)k=key(k);}
            catch(e:Dynamic)return groupCloseThrow(it,e);
            var list:JsArray;
            if(isMap) {
                var map:JsMap=cast result;var j=mapIndex(map,k);
                if(j<0){mapPut(map,k,array([]));j=mapIndex(map,k);}
                list=map.values[j];
            } else {
                var name:String=k;
                if(!result.hasOwn(name))result.setOwn(name,array([]));
                list=result.slots.get(name);
            }
            setIndex(list,list.length,value);i++;
        }
    }
    static function groupCloseThrow(it:Dynamic,reason:Dynamic):Dynamic {
        // The original throw wins over failures getting or calling return().
        try {var ret=get(it,"return");if(ret!=null && ret!=undef())call(ret,it,[]);}
        catch(_:Dynamic){}
        throw reason;
    }
    public static function objectToString(t:Dynamic):String {
        if(t==undef())return "[object Undefined]";if(t==null)return "[object Null]";
        var o=toObject(t);var tag=getKey(o,Symbols.toStringTag,o);
        if(Std.isOfType(tag,String))return "[object "+tag+"]";
        if(o.hasOwn("\x00@primitive")){var p=o.slots.get("\x00@primitive");return "[object "+(Std.isOfType(p,String)?"String":Std.isOfType(p,Bool)?"Boolean":"Number")+"]";}
        var t=o.tag();
        return "[object "+(t=="Map"||t=="Set"?"Object":t)+"]";
    }
    static function enumerableOwn(o:JsObject,k:String):Bool return o.attr(k) & Attr.HIDDEN==0;
    // All own keys (strings in order, then symbols), hidden ones included.
    public static function ownPropertyKeys(o:JsObject):Array<String> {
        var strings:Array<String>=[];var symbols:Array<String>=[];
        if(Std.isOfType(o,JsArray)){var a:JsArray=cast o;for(i in 0...a.items.length)if(a.items[i]!=hole)strings.push(Std.string(i));}
        var numeric:Array<String>=[];var other:Array<String>=[];
        if(o.names!=null)for(n in o.names)if(Symbols.isSymbolKey(n))symbols.push(n);else if(index(n)>=0)numeric.push(n);else other.push(n);
        numeric.sort((x,y)->{var a=index(x),b=index(y);return a<b?-1:a>b?1:0;});
        var extra:Array<String>=[];
        if(Std.isOfType(o,JsArray))extra.push("length");
        if(Std.isOfType(o,JsFunction)){for(k in ["length","name"])if(!o.hasOwn(k) && hasOwnKey(o,k))extra.push(k);}
        return strings.concat(numeric).concat(extra).concat(other).concat(symbols);
    }
    static function descriptor(o:JsObject,k:String):Dynamic {
        if(!hasOwnKey(o,k))return undef();
        var d=new JsObject(ObjectProto);var attribute=o.attr(k);
        var v:Dynamic=o.hasOwn(k)?o.slots.get(k):get(o,k);
        var virtual=!o.hasOwn(k);
        if(Std.isOfType(v,Accessor)){var acc:Accessor=v;d.setOwn("get",acc.getter==null?undef():acc.getter);d.setOwn("set",acc.setter==null?undef():acc.setter);}
        else {d.setOwn("value",v);d.setOwn("writable",virtual?(Std.isOfType(o,JsArray) && k=="length" || k=="prototype"):attribute & Attr.READONLY==0);}
        d.setOwn("enumerable",virtual?(Std.isOfType(o,JsArray) && k!="length"):attribute & Attr.HIDDEN==0);
        d.setOwn("configurable",virtual?(Std.isOfType(o,JsFunction) && k!="prototype" || Std.isOfType(o,JsArray) && k!="length"):attribute & Attr.LOCKED==0);
        return d;
    }
    static function defineProperties(o:JsObject,props:Dynamic):Void {
        var p=toObject(props);for(k in ownPropertyKeys(p))if(enumerableOwn(p,k))defineProperty(o,k,get(p,k));
    }
    public static function defineProperty(o:JsObject,k:String,desc:Dynamic):Void {
        if(!isObject(desc))error("TypeError","Property description must be an object: "+Seed.text(desc));
        if(!o.hasOwn(k) && Std.isOfType(o,JsFunction) && hasOwnKey(o,k))o.setOwn(k,get(o,k),k=="prototype"?Attr.HIDDEN|Attr.LOCKED:Attr.HIDDEN|Attr.READONLY);
        var exists=o.hasOwn(k);var old=exists?o.attr(k):Attr.HIDDEN|Attr.READONLY|Attr.LOCKED;
        if(exists && old & Attr.LOCKED!=0) {
            if(has(desc,"value") && !(old & Attr.READONLY!=0 && sameValue(get(desc,"value"),o.slots.get(k))) && old & Attr.READONLY!=0)error("TypeError","Cannot redefine property: "+Symbols.functionName(k));
            if(has(desc,"get") || has(desc,"set") || Seed.truth(get(desc,"configurable")))error("TypeError","Cannot redefine property: "+Symbols.functionName(k));
        }
        else if(!exists && !o.extensible)error("TypeError","Cannot define property "+Symbols.functionName(k)+", object is not extensible");
        function flag(name:String,bit:Int,attribute:Int):Int {
            if(!has(desc,name))return attribute;
            return Seed.truth(get(desc,name))?attribute & ~bit:attribute | bit;
        }
        var attribute=old;
        attribute=flag("enumerable",Attr.HIDDEN,attribute);attribute=flag("configurable",Attr.LOCKED,attribute);
        if(has(desc,"get") || has(desc,"set")) {
            var current=exists?o.slots.get(k):null;var acc=Std.isOfType(current,Accessor)?(current:Accessor):new Accessor(null,null);
            if(has(desc,"get")){var g=get(desc,"get");acc.getter=g==undef()?null:g;}
            if(has(desc,"set")){var s=get(desc,"set");acc.setter=s==undef()?null:s;}
            o.setOwn(k,acc,attribute & ~Attr.READONLY);return;
        }
        attribute=flag("writable",Attr.READONLY,attribute);
        var value=has(desc,"value")?get(desc,"value"):exists && !Std.isOfType(o.slots.get(k),Accessor)?o.slots.get(k):undef();
        if(Std.isOfType(o,JsArray)) {
            var a:JsArray=cast o;
            if(k=="length"){setLength(a,value);return;}
            var i=index(k);
            if(i>=0) {
                if(attribute==0){setIndex(a,i,value);return;}
                if(i<a.items.length)a.items[Std.int(i)]=hole;
                if(i>=a.length)a.length=i+1;
            }
        }
        o.setOwn(k,value,attribute);
    }
    static function integrity(v:Dynamic,freeze:Bool):Void {
        if(!isObject(v))return;var o:JsObject=v;
        if(Std.isOfType(o,JsArray)) {
            // (elements move to ordinary properties, which carry attributes)
            var a:JsArray=cast o;var items=a.items;a.items=[];
            for(i in 0...items.length)if(items[i]!=hole)a.setOwn(Std.string(i),items[i]);
        }
        if(o.names!=null)for(k in o.names){var attribute=o.attr(k) | Attr.LOCKED;if(freeze && !Std.isOfType(o.slots.get(k),Accessor))attribute|=Attr.READONLY;o.setOwn(k,o.slots.get(k),attribute);}
        o.extensible=false;
    }
    static function testIntegrity(v:Dynamic,frozen:Bool):Bool {
        if(!isObject(v))return true;var o:JsObject=v;
        if(o.extensible)return false;
        if(Std.isOfType(o,JsArray) && (cast o:JsArray).items.length>0)return false;
        if(o.names!=null)for(k in o.names){var attribute=o.attr(k);if(attribute & Attr.LOCKED==0)return false;if(frozen && !Std.isOfType(o.slots.get(k),Accessor) && attribute & Attr.READONLY==0)return false;}
        return true;
    }
    // Primitive wrapper objects (Object("x"), new Number(1)).
    public static function wrap(v:Dynamic):JsObject {
        var o=new JsObject(Std.isOfType(v,String)?StringProto:Std.isOfType(v,Bool)?BooleanProto:Std.isOfType(v,Symbols.JsSymbol)?SymbolProto:NumberProto);
        o.setOwn("\x00@primitive",v,Attr.HIDDEN);
        if(Std.isOfType(v,String)){var s:String=v;for(i in 0...s.length)o.setOwn(Std.string(i),s.charAt(i),Attr.READONLY|Attr.LOCKED);o.setOwn("length",s.length,Attr.HIDDEN|Attr.READONLY|Attr.LOCKED);}
        return o;
    }
    // (this value of a String/Number/Boolean method: the primitive, or a wrapper's)
    public static function primitive(t:Dynamic,type:String):Dynamic {
        if(isObject(t) && (t:JsObject).hasOwn("\x00@primitive"))t=(t:JsObject).slots.get("\x00@primitive");
        if(Seed.typeOf(t)!=type)error("TypeError",type.charAt(0).toUpperCase()+type.substr(1)+".prototype method called on incompatible receiver "+Seed.text(t));
        return t;
    }

    // Function
    static function setupFunction():Void {
        var p=FunctionProto;
        var poison=native("",0,(_,_,_)->error("TypeError","Restricted function property"));
        poison.setOwn("name","",Attr.HIDDEN|Attr.READONLY|Attr.LOCKED);poison.setOwn("length",0,Attr.HIDDEN|Attr.READONLY|Attr.LOCKED);poison.extensible=false;
        for(name in ["caller","arguments"])p.setOwn(name,new Accessor(poison,poison),Attr.HIDDEN);
        method(p,"call",1,(t,a,_)->call(t,arg(a,0),a.slice(1)));
        method(p,"apply",2,(t,a,_)->call(t,arg(a,0),arg(a,1)==null || arg(a,1)==undef()?[]:arrayLikeList(arg(a,1))));
        method(p,"bind",1,(t,a,_)->{
            var target:JsFunction=callback(t);var self=arg(a,0);var bound=a.slice(1);
            var f:JsFunction=null;
            f=native("bound "+target.name,Std.int(Math.max(0,(target.rest?target.arity-1:target.arity)-bound.length)),(_,more,nt)->nt==undef()?call(target,self,bound.concat(more)):construct(target,bound.concat(more),nt==f?target:nt),isConstructor(target));
            f.setOwn(boundTarget,target,Attr.HIDDEN);return f;
        });
        method(p,"toString",0,(t,_,_)->{if(!Std.isOfType(t,JsFunction))error("TypeError","Function.prototype.toString requires that 'this' be a Function");var f:JsFunction=cast t;return (f.kind>=JsFunction.BASE?"class "+f.name+" { }":"function "+f.name+"() { [native code] }");});
        method(p,Symbols.hasInstance,1,(t,a,_)->{if(!Std.isOfType(t,JsFunction))return false;var p=get(t,"prototype");var v=arg(a,0);if(!isObject(v) || !isObject(p))return false;var o=(v:JsObject).proto;while(o!=null){if(o==p)return true;o=o.proto;}return false;});
        var c=constructor("Function",1,p,(_,_,_)->error("EvalError","Code generation from strings is not supported"));
    }
    public static function arrayLikeList(o:Dynamic):Array<Dynamic> {
        if(!isObject(o))return error("TypeError","CreateListFromArrayLike called on non-object");
        var n=Std.int(Math.min(lengthOf(o),1e7));return [for(i in 0...n)get(o,i)];
    }
    public static function lengthOf(o:Dynamic):Float {
        if(Std.isOfType(o,JsArray))return (o:JsArray).length;
        var n=toIntegerOrInfinity(get(o,"length"));return Math.max(0,Math.min(n,9007199254740991.0));
    }

    // Array
    static function hasAt(o:Dynamic,i:Float):Bool {
        if(Std.isOfType(o,JsArray)){var a:JsArray=cast o;if(i<a.items.length)return a.items[Std.int(i)]!=hole;}
        return has(o,Seed.numberText(i));
    }
    static function setAt(o:Dynamic,i:Float,v:Dynamic):Void put(o,i,v);
    static function deleteAt(o:Dynamic,i:Float):Void remove(o,Seed.numberText(i));
    static function relative(v:Dynamic,len:Float):Float {var n=toIntegerOrInfinity(v);return n<0?Math.max(len+n,0):Math.min(n,len);}
    static function setupArray():Void {
        var p=ArrayProto;
        var c=constructor("Array",1,p,(_,a,nt)->{
            var r:JsArray=cast array(a.length==1 && isNumber(a[0])?[]:a.copy());
            if(a.length==1 && isNumber(a[0]))setLength(r,a[0]);
            r.proto=protoFrom(nt,ArrayProto);return r;
        });
        getter(c,"\x00@@species",t->t);
        var unscopables=new JsObject(null);
        for(name in ["at","copyWithin","entries","fill","find","findIndex","findLast","findLastIndex","flat","flatMap","includes","keys","toReversed","toSorted","toSpliced","values"])unscopables.setOwn(name,true);
        p.setOwn("\x00@@unscopables",unscopables,Attr.HIDDEN|Attr.READONLY);
        method(c,"isArray",1,(_,a,_)->Std.isOfType(arg(a,0),JsArray));
        method(c,"of",0,(_,a,_)->array(a.copy()));
        method(c,"from",1,(_,a,_)->{
            var source=arg(a,0);var f=arg(a,1);var mapped=f!=undef();if(mapped)callback(f);
            if(source==null || source==undef())error("TypeError",Seed.text(source)+" is not iterable");
            var values=getKey(source,Symbols.iterator,source)!=undef()?toList(source):arrayLikeList(toObject(source));
            if(mapped)for(i in 0...values.length)values[i]=call(f,arg(a,2),[values[i],i]);
            return array(values);
        });
        method(p,"push",1,(t,a,_)->{
            if(Std.isOfType(t,JsArray)){var arr:JsArray=cast t;if(arr.items.length==arr.length && arr.extensible){for(v in a)arr.items.push(v);arr.length=arr.items.length;return arr.length;}}
            var o=toObject(t);var n=lengthOf(o);for(v in a)setAt(o,n++,v);put(o,"length",n);return n;
        });
        method(p,"pop",0,(t,_,_)->{var o=toObject(t);var n=lengthOf(o);if(n==0){put(o,"length",0);return undef();}var v=get(o,n-1);deleteAt(o,n-1);put(o,"length",n-1);return v;});
        method(p,"shift",0,(t,_,_)->{
            var o=toObject(t);var n=lengthOf(o);if(n==0){put(o,"length",0);return undef();}
            if(Std.isOfType(o,JsArray)){var arr:JsArray=cast o;if(arr.items.length==n && arr.extensible){var v=arr.items.shift();arr.length--;return v==hole?undef():v;}}
            var v=get(o,0);var i:Float=1;while(i<n){if(hasAt(o,i))setAt(o,i-1,get(o,i));else deleteAt(o,i-1);i++;}deleteAt(o,n-1);put(o,"length",n-1);return v;
        });
        method(p,"unshift",1,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var count=a.length;var i=n;while(i>0){i--;if(hasAt(o,i))setAt(o,i+count,get(o,i));else deleteAt(o,i+count);}for(j in 0...count)setAt(o,j,a[j]);put(o,"length",n+count);return n+count;});
        method(p,"join",1,(t,a,_)->join(toObject(t),arg(a,0)==undef()?",":Seed.text(arg(a,0))));
        method(p,"toString",0,(t,_,_)->{var o=toObject(t);var j=get(o,"join");return isCallable(j)?call(j,o,[]):objectToString(o);});
        method(p,"toLocaleString",0,(t,_,_)->join(toObject(t),","));
        method(p,"slice",2,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var start=relative(arg(a,0),n);var end=arg(a,1)==undef()?n:relative(arg(a,1),n);var out=new JsArray(ArrayProto);var i=start;var k:Float=0;while(i<end){if(hasAt(o,i))setIndex(out,k,get(o,i));k++;i++;}out.length=Math.max(k,0);return out;});
        method(p,"at",1,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var i=toIntegerOrInfinity(arg(a,0));if(i<0)i+=n;return i<0||i>=n?undef():get(o,i);});
        method(p,"indexOf",1,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var i=arg(a,1)==undef()?0:toIntegerOrInfinity(arg(a,1));if(i<0)i=Math.max(i+n,0);var x=arg(a,0);while(i<n){if(hasAt(o,i) && Seed.strictEq(get(o,i),x))return i;i++;}return -1;});
        method(p,"lastIndexOf",1,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var i=a.length<2?n-1:toIntegerOrInfinity(arg(a,1));if(i<0)i+=n;else i=Math.min(i,n-1);var x=arg(a,0);while(i>=0){if(hasAt(o,i) && Seed.strictEq(get(o,i),x))return i;i--;}return -1;});
        method(p,"includes",1,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var i=arg(a,1)==undef()?0:toIntegerOrInfinity(arg(a,1));if(i<0)i=Math.max(i+n,0);var x=arg(a,0);while(i<n){if(sameValueZero(get(o,i),x))return true;i++;}return false;});
        for(name in ["map","filter","forEach","some","every","find","findIndex","findLast","findLastIndex"]) method(p,name,1,function(t:Dynamic,a:Array<Dynamic>,_:Dynamic):Dynamic {
            var o=toObject(t);var n=lengthOf(o);var f=callback(arg(a,0));var self=arg(a,1);
            var out=new JsArray(ArrayProto);if(name=="map")out.length=n;
            var reverse=name=="findLast"||name=="findLastIndex";var visitAll=StringTools.startsWith(name,"find");var i:Float=reverse?n-1:0;
            while(i>=0 && i<n) {
                if(visitAll || hasAt(o,i)) {
                    var v=get(o,i);var result=call(f,self,[v,i,o]);
                    switch(name) {
                        case "map":setIndex(out,i,result);
                        case "filter":if(Seed.truth(result))setIndex(out,out.length,v);
                        case "some":if(Seed.truth(result))return true;
                        case "every":if(!Seed.truth(result))return false;
                        case "find"|"findLast":if(Seed.truth(result))return v;
                        case "findIndex"|"findLastIndex":if(Seed.truth(result))return i;
                        case _:
                    }
                }
                i+=reverse?-1:1;
            }
            return switch(name){case "map"|"filter":out;case "some":false;case "every":true;case "find"|"findLast"|"forEach":undef();case _:-1;};
        });
        for(name in ["reduce","reduceRight"]) method(p,name,1,(t,a,_)->{
            var o=toObject(t);var n=lengthOf(o);var f=callback(arg(a,0));var reverse=name=="reduceRight";var i:Float=reverse?n-1:0;var acc=arg(a,1);var ready=a.length>=2;
            while(i>=0 && i<n){if(hasAt(o,i)){if(!ready){acc=get(o,i);ready=true;}else acc=call(f,undef(),[acc,get(o,i),i,o]);}i+=reverse?-1:1;}
            if(!ready)error("TypeError","Reduce of empty array with no initial value");return acc;
        });
        method(p,"reverse",0,(t,_,_)->{var o=toObject(t);var n=lengthOf(o);var left:Float=0;while(left<Math.ffloor(n/2)){var right=n-left-1;var l=hasAt(o,left),r=hasAt(o,right);var lv=get(o,left),rv=get(o,right);if(r)setAt(o,left,rv);else deleteAt(o,left);if(l)setAt(o,right,lv);else deleteAt(o,right);left++;}return o;});
        method(p,"toReversed",0,(t,_,_)->{var o=toObject(t);var n=lengthOf(o);return array([for(i in 0...Std.int(n))get(o,n-1-i)]);});
        method(p,"fill",1,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var i=relative(arg(a,1),n);var end=arg(a,2)==undef()?n:relative(arg(a,2),n);while(i<end)setAt(o,i++,arg(a,0));return o;});
        method(p,"concat",1,(t,a,_)->{
            var out=new JsArray(ArrayProto);
            for(item in ([toObject(t)]:Array<Dynamic>).concat(a)) {
                var spreadable=getKey(item,"\x00@@isConcatSpreadable",item);
                if(spreadable==undef()?Std.isOfType(item,JsArray):Seed.truth(spreadable)){var n=lengthOf(item);var i:Float=0;var start=out.length;while(i<n){if(hasAt(item,i))setIndex(out,start+i,get(item,i));i++;}out.length=start+n;}
                else setIndex(out,out.length,item);
            }
            return out;
        });
        method(p,"keys",0,(t,_,_)->new JsIterator(ArrayIteratorProto,toObject(t),"keys"));
        method(p,"entries",0,(t,_,_)->new JsIterator(ArrayIteratorProto,toObject(t),"entries"));
        var values=native("values",0,(t,_,_)->new JsIterator(ArrayIteratorProto,toObject(t),"values"));
        p.setOwn("values",values,Attr.HIDDEN);p.setOwn(Symbols.iterator,values,Attr.HIDDEN);
        for(name in ["splice","toSpliced"]) method(p,name,2,(t,a,_)->{
            var o=toObject(t);var n=lengthOf(o);var start=relative(arg(a,0),n);
            var count=a.length==0?0:a.length==1?n-start:Math.min(Math.max(toIntegerOrInfinity(arg(a,1)),0),n-start);
            var inserted=a.slice(2);
            if(name=="toSpliced"){var out=[];var i:Float=0;while(i<start)out.push(get(o,i++));for(v in inserted)out.push(v);i=start+count;while(i<n)out.push(get(o,i++));return array(out);}
            var removed=new JsArray(ArrayProto);var k:Float=0;while(k<count){if(hasAt(o,start+k))setIndex(removed,k,get(o,start+k));k++;}removed.length=count;
            var delta=inserted.length-count;
            if(delta<0){var i=start;while(i<n-count){var from=i+count,to=i+inserted.length;if(hasAt(o,from))setAt(o,to,get(o,from));else deleteAt(o,to);i++;}var j=n;while(j>n+delta){deleteAt(o,j-1);j--;}}
            else if(delta>0){var i=n-count;while(i>start){var from=i+count-1,to=i+inserted.length-1;if(hasAt(o,from))setAt(o,to,get(o,from));else deleteAt(o,to);i--;}}
            for(j in 0...inserted.length)setAt(o,start+j,inserted[j]);
            put(o,"length",n+delta);return removed;
        });
        for(name in ["sort","toSorted"]) method(p,name,1,(t,a,_)->{
            var cmp=arg(a,0);if(cmp!=undef())callback(cmp);
            var o=toObject(t);var n=lengthOf(o);var present=[];var undefineds=0;var i:Float=0;
            while(i<n){if(name=="toSorted" || hasAt(o,i)){var v=get(o,i);if(v==undef())undefineds++;else present.push(v);}i++;}
            present=mergeSort(present,(x,y)->cmp==undef()?compareStrings(Seed.text(x),Seed.text(y)):{var r=Seed.numeric(call(cmp,undef(),[x,y]));r>0?1:r<0?-1:0;});
            var target:Dynamic=name=="sort"?o:new JsArray(ArrayProto);var k:Float=0;
            for(v in present)setAt(target,k++,v);for(_ in 0...undefineds)setAt(target,k++,undef());
            if(name=="sort")while(k<n)deleteAt(target,k++);
            return target;
        });
        method(p,"copyWithin",2,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var target=relative(arg(a,0),n),start=relative(arg(a,1),n),end=arg(a,2)==undef()?n:relative(arg(a,2),n);var count=Math.min(end-start,n-target);var direction:Float=1;if(start<target && target<start+count){direction=-1;start+=count-1;target+=count-1;}while(count>0){if(hasAt(o,start))setAt(o,target,get(o,start));else deleteAt(o,target);start+=direction;target+=direction;count--;}return o;});
        method(p,"flat",0,(t,a,_)->{var o=toObject(t);var out=new JsArray(ArrayProto);var depth=arg(a,0)==undef()?1:Math.max(toIntegerOrInfinity(arg(a,0)),0);flatten(out,o,depth+1);return out;});
        method(p,"flatMap",1,(t,a,_)->{var o=toObject(t);var f=callback(arg(a,0));var out=new JsArray(ArrayProto);var n=lengthOf(o);var i:Float=0;while(i<n){if(hasAt(o,i))flatten(out,call(f,arg(a,1),[get(o,i),i,o]),1);i++;}return out;});
        method(p,"with",2,(t,a,_)->{var o=toObject(t);var n=lengthOf(o);var i=toIntegerOrInfinity(arg(a,0));if(i<0)i+=n;if(i<0 || i>=n)error("RangeError","Invalid index : "+Seed.text(arg(a,0)));return array([for(j in 0...Std.int(n))j==i?arg(a,1):get(o,j)]);});
    }
    static function join(o:Dynamic,sep:String):String {
        var n=lengthOf(o);var b=new StringBuf();var i:Float=0;
        if(cycle.indexOf(o)>=0)return "";cycle.push(o);
        try {while(i<n){if(i>0)b.add(sep);var v=get(o,i++);if(v!=null && v!=undef())b.add(Seed.text(v));}}
        catch(e:Dynamic){cycle.pop();throw e;}
        cycle.pop();return b.toString();
    }
    static var cycle:Array<Dynamic>=[];
    static function flatten(out:JsArray,v:Dynamic,depth:Float):Void {
        if(depth>0 && Std.isOfType(v,JsArray)){var n=lengthOf(v);var i:Float=0;while(i<n){if(hasAt(v,i))flatten(out,get(v,i),depth-1);i++;}}
        else setIndex(out,out.length,v);
    }
    static function mergeSort(values:Array<Dynamic>,cmp:(Dynamic,Dynamic)->Int):Array<Dynamic> {
        if(values.length<2)return values;
        var mid=values.length>>1;var left=mergeSort(values.slice(0,mid),cmp),right=mergeSort(values.slice(mid),cmp);
        var out=[];var i=0,j=0;
        while(i<left.length && j<right.length)out.push(cmp(left[i],right[j])<=0?left[i++]:right[j++]);
        while(i<left.length)out.push(left[i++]);while(j<right.length)out.push(right[j++]);
        return out;
    }

    // String
    static function thisString(t:Dynamic):String {
        if(t==null || t==undef())error("TypeError","String.prototype method called on null or undefined");
        if(Std.isOfType(t,String))return t;
        return Seed.text(isObject(t)?toPrimitive(t,"string"):t);
    }
    static function setupString():Void {
        var p=StringProto;constant(p,"length",0);p.setOwn("\x00@primitive","",Attr.HIDDEN);
        var c=constructor("String",1,p,(_,a,nt)->{
            var v=a.length==0?"":Std.isOfType(a[0],Symbols.JsSymbol) && nt==undef()?Symbols.text(a[0]):Seed.text(isObject(a[0])?toPrimitive(a[0],"string"):a[0]);
            if(nt==undef())return (v:Dynamic);var o=wrap(v);o.proto=protoFrom(nt,StringProto);return o;
        });
        method(c,"fromCharCode",1,(_,a,_)->{var out=new StringBuf();for(v in a)out.addChar(toInt32(v)&65535);return out.toString();});
        method(c,"fromCodePoint",1,(_,a,_)->{var out=new StringBuf();for(v in a){var n=Seed.numeric(v);if(!Math.isFinite(n)||Math.ffloor(n)!=n || n<0 || n>0x10ffff)error("RangeError","Invalid code point "+Seed.text(v));var i=Std.int(n);if(i<65536)out.addChar(i);else{i-=65536;out.addChar(0xd800+(i>>10));out.addChar(0xdc00+(i&1023));}}return out.toString();});
        method(c,"raw",1,(_,a,_)->{var strings=get(arg(a,0),"raw");var n=lengthOf(strings);var out=new StringBuf();var i:Float=0;while(i<n){out.add(Seed.text(get(strings,i)));if(i+1<n && i+1<a.length)out.add(Seed.text(a[Std.int(i+1)]));i++;}return out.toString();});
        method(p,"toString",0,(t,_,_)->primitive(t,"string"));
        method(p,"valueOf",0,(t,_,_)->primitive(t,"string"));
        var names=["charAt","at","charCodeAt","codePointAt","slice","substring","substr","concat","indexOf","includes","startsWith","lastIndexOf","endsWith",
            "toLowerCase","toUpperCase","toLocaleLowerCase","toLocaleUpperCase","trim","trimStart","trimEnd","trimLeft","trimRight","repeat","padStart","padEnd",
            "split","replace","replaceAll","localeCompare","normalize","isWellFormed","toWellFormed","search","match","matchAll"];
        for(name in names)method(p,name,stringArity(name),(t,a,_)->stringMethod(thisString(t),name,a));
        method(p,Symbols.iterator,0,(t,_,_)->new JsIterator(StringIteratorProto,thisString(t),"values"));
    }
    static function stringArity(name:String):Int return switch(name) {
        case "toLowerCase"|"toUpperCase"|"toLocaleLowerCase"|"toLocaleUpperCase"|"trim"|"trimStart"|"trimEnd"|"trimLeft"|"trimRight"|"normalize"|"isWellFormed"|"toWellFormed":0;
        case "slice"|"substring"|"substr"|"split"|"replace"|"replaceAll":2;
        case _:1;
    };
    public static function stringMethod(s:String,name:String,args:Array<Dynamic>):Dynamic {
        var first=arg(args,0),second=arg(args,1);var n=s.length;
        switch(name) {
            case "charAt"|"at"|"charCodeAt"|"codePointAt":
                var i=toIntegerOrInfinity(first);if(name=="at" && i<0)i+=n;if(i<0 || i>=n)return name=="charAt"?"":name=="charCodeAt"?Math.NaN:undef();var c=s.charCodeAt(Std.int(i));
                if(name=="codePointAt" && c>=0xd800 && c<=0xdbff && i+1<n){var d=s.charCodeAt(Std.int(i+1));if(d>=0xdc00 && d<=0xdfff)return (c-0xd800)*1024+(d-0xdc00)+65536;}
                return name=="charCodeAt" || name=="codePointAt"?c:s.charAt(Std.int(i));
            case "slice":var start=relative(first,n),end=second==undef()?n:relative(second,n);return s.substring(Std.int(start),Std.int(Math.max(start,end)));
            case "substring":var start=Math.max(0,Math.min(toIntegerOrInfinity(first),n)),end=second==undef()?n:Math.max(0,Math.min(toIntegerOrInfinity(second),n));return s.substring(Std.int(Math.min(start,end)),Std.int(Math.max(start,end)));
            case "substr":var start=relative(first,n);var length=second==undef()?n-start:Math.min(Math.max(toIntegerOrInfinity(second),0),n-start);return length<=0?"":s.substr(Std.int(start),Std.int(length));
            case "concat":var b=new StringBuf();b.add(s);for(a in args)b.add(Seed.text(a));return b.toString();
            case "indexOf"|"includes"|"startsWith":
                if(name!="indexOf" && Regex.isRegExp(first))error("TypeError","First argument to String.prototype."+name+" must not be a regular expression");
                var needle=Seed.text(first);var start=Std.int(Math.max(0,Math.min(toIntegerOrInfinity(second),n)));
                if(name=="startsWith")return s.substr(start,needle.length)==needle;
                var i=s.indexOf(needle,start);return name=="indexOf"?i:i>=0;
            case "lastIndexOf":var num=Seed.numeric(second);var pos=Math.isNaN(num)?n:Std.int(Math.max(0,Math.min(toIntegerOrInfinity(num),n)));return s.lastIndexOf(Seed.text(first),Std.int(pos));
            case "endsWith":if(Regex.isRegExp(first))error("TypeError","First argument to String.prototype.endsWith must not be a regular expression");var needle=Seed.text(first);var end=second==undef()?n:Std.int(Math.max(0,Math.min(toIntegerOrInfinity(second),n)));return end>=needle.length && s.substr(end-needle.length,needle.length)==needle;
            case "toLowerCase"|"toLocaleLowerCase":return s.toLowerCase();case "toUpperCase"|"toLocaleUpperCase":return s.toUpperCase();
            case "trim"|"trimStart"|"trimEnd"|"trimLeft"|"trimRight":var start=0,end=n;if(name!="trimEnd" && name!="trimRight")while(start<end && Seed.whitespace(s.charCodeAt(start)))start++;if(name!="trimStart" && name!="trimLeft")while(end>start && Seed.whitespace(s.charCodeAt(end-1)))end--;return s.substring(start,end);
            case "repeat":var count=toIntegerOrInfinity(first);if(count<0 || !Math.isFinite(count))error("RangeError","Invalid count value: "+Seed.text(first));if(count*s.length>536870888)error("RangeError","Invalid string length");var b=new StringBuf();var i:Float=0;while(i<count){b.add(s);i++;}return b.toString();
            case "padStart"|"padEnd":var target=toIntegerOrInfinity(first);var fill=second==undef()?" ":Seed.text(second);if(target<=n || fill=="")return s;if(target>536870888)error("RangeError","Invalid string length");var padding=new StringBuf();var needed=Std.int(target-n);while(padding.length<needed)padding.add(fill);var pad=padding.toString().substr(0,needed);return name=="padStart"?pad+s:s+pad;
            case "localeCompare":return collate(s,Seed.text(first));
            case "normalize":
                var form=first==undef()?"NFC":Seed.text(first);
                if(["NFC","NFD","NFKC","NFKD"].indexOf(form)<0)return error("RangeError","Invalid normalization form");
                return Normalization.normalize(s,form);
            case "isWellFormed"|"toWellFormed":
                var b=new StringBuf();var ok=true;var i=0;
                while(i<n){var c=s.charCodeAt(i);if(c>=0xd800 && c<=0xdbff && i+1<n && s.charCodeAt(i+1)>=0xdc00 && s.charCodeAt(i+1)<=0xdfff){b.addChar(c);b.addChar(s.charCodeAt(i+1));i+=2;continue;}if(c>=0xd800 && c<=0xdfff){ok=false;b.addChar(0xfffd);}else b.addChar(c);i++;}
                return name=="isWellFormed"?ok:b.toString();
            case "split":
                if(first!=null && first!=undef()){var splitter=getKey(first,"\x00@@split",first);if(splitter!=undef() && splitter!=null)return call(splitter,first,[s,second]);}
                var limit=second==undef()?4294967295.0:toUint32(second);var out=new JsArray(ArrayProto);if(limit==0)return out;if(first==undef()){setIndex(out,0,s);return out;}var delimiter=Seed.text(first);
                if(delimiter==""){var i=0;while(i<n && out.length<limit)setIndex(out,out.length,s.charAt(i++));return out;}
                var start=0;while(out.length<limit){var i=s.indexOf(delimiter,start);if(i<0){setIndex(out,out.length,s.substr(start));break;}setIndex(out,out.length,s.substring(start,i));start=i+delimiter.length;}return out;
            case "replace"|"replaceAll":
                if(first!=null && first!=undef()){
                    if(name=="replaceAll" && Regex.isRegExp(first) && Seed.text(get(first,"flags")).indexOf("g")<0)error("TypeError","replaceAll must be called with a global RegExp");
                    var replacer=getKey(first,"\x00@@replace",first);if(replacer!=undef() && replacer!=null)return call(replacer,first,[s,second]);
                }
                var search=Seed.text(first);var functional=isCallable(second);var replacement=functional?"":Seed.text(second);var b=new StringBuf();var start=0;var pos=s.indexOf(search);
                while(pos>=0){b.add(s.substring(start,pos));b.add(functional?Seed.text(call(second,undef(),[search,pos,s])):Regex.expand(replacement,search,s,pos,[],null));start=pos+search.length;if(name=="replace")break;if(search==""){if(pos>=n)break;b.add(s.charAt(pos));start=pos+1;}pos=s.indexOf(search,start);}
                b.add(s.substr(start));return b.toString();
            case "search"|"match"|"matchAll":
                var symbol=name=="search"?"\x00@@search":name=="match"?"\x00@@match":"\x00@@matchAll";
                if(first!=null && first!=undef()){
                    if(name=="matchAll" && Regex.isRegExp(first) && Seed.text(get(first,"flags")).indexOf("g")<0)error("TypeError","String.prototype.matchAll called with a non-global RegExp argument");
                    var m=getKey(first,symbol,first);if(m!=undef() && m!=null)return call(m,first,[s]);
                }
                var re=Regex.create(first==undef()?"":Seed.text(first),name=="matchAll"?"g":"");
                return call(get(re,symbol),re,[s]);
            case _:return error("TypeError","String.prototype."+name+" is not implemented");
        }
    }

    // localeCompare: an approximation of ICU's root collation in three levels:
    // base characters (punctuation, then digits, then letters with Latin
    // accents folded), then accents, then case (lowercase first).
    static var accents="ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿÑñÇç";
    static var bases="AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOOooooooUUUUuuuuYyyNnCc";
    static function baseOf(c:Int):Int {var k=accents.indexOf(String.fromCharCode(c));return k>=0?bases.charCodeAt(k):c;}
    static function primary(c:Int):Int {
        var b=baseOf(c);
        if(b>=65 && b<=90)b+=32;
        if(b>=97 && b<=122)return 30000+b;
        if(b>=48 && b<=57)return 20000+b;
        if(b>=0xc0)return 40000+String.fromCharCode(b).toLowerCase().charCodeAt(0);
        return 10000+b;
    }
    public static function collate(a:String,b:String):Int {
        var n=Std.int(Math.min(a.length,b.length));
        for(i in 0...n){var x=primary(a.charCodeAt(i)),y=primary(b.charCodeAt(i));if(x!=y)return x<y?-1:1;}
        if(a.length!=b.length)return a.length<b.length?-1:1;
        for(i in 0...n){var x=a.charCodeAt(i),y=b.charCodeAt(i);var ax=baseOf(x)!=x,ay=baseOf(y)!=y;if(ax!=ay)return ax?1:-1;}
        for(i in 0...n){var x=a.charCodeAt(i),y=b.charCodeAt(i);if(x==y)continue;var lx=String.fromCharCode(x).toLowerCase().charCodeAt(0)==x,ly=String.fromCharCode(y).toLowerCase().charCodeAt(0)==y;if(lx!=ly)return lx?-1:1;}
        return compareStrings(a,b)<0?-1:compareStrings(a,b)>0?1:0;
    }
    // Number, Boolean, Symbol
    static function setupNumber():Void {
        var p=NumberProto;p.setOwn("\x00@primitive",0.0,Attr.HIDDEN);
        var c=constructor("Number",1,p,(_,a,nt)->{var v:Float=a.length==0?0:Seed.numeric(isObject(a[0])?toPrimitive(a[0],"number"):a[0]);if(nt==undef())return (v:Dynamic);var o=wrap(v);o.proto=protoFrom(nt,NumberProto);return o;});
        method(c,"isNaN",1,(_,a,_)->isNumber(arg(a,0)) && Math.isNaN(arg(a,0)));
        method(c,"isFinite",1,(_,a,_)->isNumber(arg(a,0)) && Math.isFinite(arg(a,0)));
        method(c,"isInteger",1,(_,a,_)->{var v=arg(a,0);return isNumber(v) && Math.isFinite(v) && Math.ffloor(v)==v;});
        method(c,"isSafeInteger",1,(_,a,_)->{var v=arg(a,0);return isNumber(v) && Math.isFinite(v) && Math.ffloor(v)==v && Math.abs(v)<=9007199254740991.0;});
        constant(c,"NaN",Math.NaN);constant(c,"POSITIVE_INFINITY",Math.POSITIVE_INFINITY);constant(c,"NEGATIVE_INFINITY",Math.NEGATIVE_INFINITY);
        constant(c,"MAX_SAFE_INTEGER",9007199254740991.0);constant(c,"MIN_SAFE_INTEGER",-9007199254740991.0);constant(c,"EPSILON",2.220446049250313e-16);
        constant(c,"MAX_VALUE",1.7976931348623157e308);constant(c,"MIN_VALUE",5e-324);
        method(p,"valueOf",0,(t,_,_)->primitive(t,"number"));
    }
    static function setupBoolean():Void {
        var p=BooleanProto;p.setOwn("\x00@primitive",false,Attr.HIDDEN);
        constructor("Boolean",1,p,(_,a,nt)->{var v=Seed.truth(arg(a,0));if(nt==undef())return (v:Dynamic);var o=wrap(v);o.proto=protoFrom(nt,BooleanProto);return o;});
        method(p,"toString",0,(t,_,_)->primitive(t,"boolean")?"true":"false");
        method(p,"valueOf",0,(t,_,_)->primitive(t,"boolean"));
    }
    static function setupSymbol():Void {
        var p=SymbolProto;
        var c=constructor("Symbol",0,p,(_,a,nt)->{if(nt!=undef())error("TypeError","Symbol is not a constructor");return Symbols.create(arg(a,0)==undef()?undef():Seed.text(arg(a,0)));});
        for(name in ["iterator","asyncIterator","hasInstance","toPrimitive","toStringTag","isConcatSpreadable","match","matchAll","replace","search","split","species","unscopables","dispose","asyncDispose"])constant(c,name,Symbols.wellKnown(name));
        method(c,"for",1,(_,a,_)->Symbols.symbolFor(Seed.text(arg(a,0))));
        method(c,"keyFor",1,(_,a,_)->{var s=arg(a,0);if(!Std.isOfType(s,Symbols.JsSymbol))error("TypeError",Seed.text(s)+" is not a symbol");for(k=>v in Symbols.registry)if(v==s)return k;return undef();});
        method(p,"toString",0,(t,_,_)->Symbols.text(primitive(t,"symbol")));
        method(p,"valueOf",0,(t,_,_)->primitive(t,"symbol"));
        getter(p,"description",t->(primitive(t,"symbol"):Symbols.JsSymbol).description);
        p.setOwn(Symbols.toStringTag,"Symbol",Attr.HIDDEN|Attr.READONLY);
        method(p,Symbols.toPrimitive,1,(t,_,_)->primitive(t,"symbol"));
    }

    // Errors
    public static function makeError(name:String,message:String):Dynamic {
        if(!ready)init();
        var c=errors.exists(name)?errors.get(name):errors.get("Error");
        return construct(c,[message],c);
    }
    static function setupErrors():Void {
        var base:JsFunction=null;
        for(name in ["Error","TypeError","RangeError","ReferenceError","SyntaxError","URIError","EvalError","AggregateError","Test262Error"]) {
            var p=name=="Error"?ErrorProto:new JsObject(ErrorProto);
            p.setOwn("name",name,Attr.HIDDEN);p.setOwn("message","",Attr.HIDDEN);
            var aggregate=name=="AggregateError";
            var c:JsFunction=null;
            c=constructor(name,aggregate?2:1,p,(_,a,nt)->{
                var o=new JsError(protoFrom(nt==undef()?c:nt,p));
                var message=arg(a,aggregate?1:0);if(message!=undef())o.setOwn("message",Seed.text(message),Attr.HIDDEN);
                var options=arg(a,aggregate?2:1);if(isObject(options) && has(options,"cause"))o.setOwn("cause",get(options,"cause"),Attr.HIDDEN);
                if(aggregate)o.setOwn("errors",array(toList(arg(a,0))),Attr.HIDDEN);
                o.setOwn("stack",new Accessor(native("stack",0,(t,_,_)->errorText(t)+"\n    at <anonymous>"),native("stack",1,(t,v,_)->{(t:JsObject).setOwn("stack",arg(v,0),Attr.HIDDEN);return undef();})),Attr.HIDDEN);
                return o;
            });
            if(name=="Error"){base=c;method(c,"isError",1,(_,a,_)->Std.isOfType(arg(a,0),JsError));method(p,"toString",0,(t,_,_)->{if(!isObject(t))error("TypeError","Error.prototype.toString called on non-object");return errorText(t);});}
            else c.proto=base;
            errors.set(name,c);
        }
    }
    public static function errorText(t:Dynamic):String {
        var name=get(t,"name");var message=get(t,"message");
        var n=name==undef()?"Error":Seed.text(name);var m=message==undef()?"":Seed.text(message);
        return n==""?m:m==""?n:n+": "+m;
    }

    // Iterators
    static function setupIterators():Void {
        method(IteratorProto,Symbols.iterator,0,(t,_,_)->t);
        for(p in [ArrayIteratorProto,MapIteratorProto,SetIteratorProto,StringIteratorProto])
            method(p,"next",0,(t,_,_)->{if(!Std.isOfType(t,JsIterator))error("TypeError","next method called on incompatible receiver "+Seed.text(t));return iteratorNext(t);});
        ArrayIteratorProto.setOwn(Symbols.toStringTag,"Array Iterator",Attr.HIDDEN|Attr.READONLY);
        MapIteratorProto.setOwn(Symbols.toStringTag,"Map Iterator",Attr.HIDDEN|Attr.READONLY);
        SetIteratorProto.setOwn(Symbols.toStringTag,"Set Iterator",Attr.HIDDEN|Attr.READONLY);
        StringIteratorProto.setOwn(Symbols.toStringTag,"String Iterator",Attr.HIDDEN|Attr.READONLY);
    }
    public static function iteratorNext(it:JsIterator):Dynamic {
        var v=it.finished?finished:iteratorStep(it);
        if(v==finished){it.finished=true;return object(["value","done"],[undef(),true]);}
        return object(["value","done"],[v,false]);
    }
    public static function iteratorStep(it:JsIterator):Dynamic {
        var target:Dynamic=it.target;
        if(Std.isOfType(target,JsMap)) {
            var m:JsMap=target;
            while(it.index<m.keys.length) {
                var i=Std.int(it.index++);if(!m.active[i])continue;
                return it.kind=="keys"?m.keys[i]:it.kind=="entries"?array([m.keys[i],m.values[i]]):m.values[i];
            }
            return finished;
        }
        if(Std.isOfType(target,String)) {
            var s:String=target;if(it.index>=s.length)return finished;
            var i=Std.int(it.index++);var c=s.charCodeAt(i);
            // (iteration combines a valid surrogate pair, unlike indexed access)
            if(c>=0xd800 && c<=0xdbff && it.index<s.length){var low=s.charCodeAt(i+1);if(low>=0xdc00 && low<=0xdfff){it.index++;return s.substr(i,2);}}
            return s.charAt(i);
        }
        if(it.index>=lengthOf(target))return finished;
        var i=it.index++;
        return it.kind=="keys"?i:it.kind=="entries"?array([i,get(target,i)]):get(target,i);
    }

    // Map and Set
    static function thisMap(t:Dynamic,isSet:Bool,name:String,weak=false):JsMap {
        if(!Std.isOfType(t,JsMap) || (t:JsMap).isSet!=isSet || (t:JsMap).weak!=weak)error("TypeError","Method "+(weak?"Weak":"")+(isSet?"Set":"Map")+".prototype."+name+" called on incompatible receiver "+Inspect.inspect(t));
        return t;
    }
    // (keys are compared with SameValueZero; an index maps each key to its slot)
    static function mapIndex(m:JsMap,k:Dynamic):Int {
        var id=mapKey(k);if(id!=null){var index=MapIndex.strings(m);return index.exists(id)?index.get(id):-1;}
        var index=MapIndex.objects(m);return index.exists(k)?index.get(k):-1;
    }
    static function mapKey(k:Dynamic):String {
        if(Std.isOfType(k,String))return "s"+k;
        if(isNumber(k)){var n:Float=k;return Math.isNaN(n)?"NaN":"n"+Seed.numberText(n==0?0:n);}
        if(k==undef())return "u";if(k==null)return "l";if(Std.isOfType(k,Bool))return k?"t":"f";
        return null;
    }
    public static function mapPut(m:JsMap,k:Dynamic,v:Dynamic):JsMap {
        if(isNumber(k) && Seed.numeric(k)==0)k=0.0;
        if(m.isSet)v=k;
        var i=mapIndex(m,k);
        if(i>=0){m.values[i]=v;return m;}
        var slot=m.keys.length;m.keys.push(k);m.values.push(v);m.active.push(true);
        var id=mapKey(k);if(id!=null)MapIndex.strings(m).set(id,slot);else MapIndex.objects(m).set(k,slot);
        return m;
    }
    static function mapDelete(m:JsMap,k:Dynamic):Bool {
        var i=mapIndex(m,k);if(i<0)return false;
        m.active[i]=false;m.keys[i]=undef();m.values[i]=undef();
        var id=mapKey(k);if(id!=null)MapIndex.strings(m).remove(id);else MapIndex.objects(m).remove(k);
        return true;
    }
    static function setupCollections():Void {
        for(isSet in [false,true]) {
            var p=isSet?SetProto:MapProto;var name=isSet?"Set":"Map";
            var c=constructor(name,0,p,(_,a,nt)->{
                if(nt==undef())error("TypeError","Constructor "+name+" requires 'new'");
                var m=new JsMap(protoFrom(nt,p),isSet);var source=arg(a,0);
                if(source!=undef() && source!=null) {
                    var adder=get(m,isSet?"add":"set");
                    for(v in toList(source)){if(isSet)call(adder,m,[v]);else{if(!isObject(v))error("TypeError","Iterator value "+Seed.text(v)+" is not an entry object");call(adder,m,[get(v,0),get(v,1)]);}}
                }
                return m;
            });
            getter(c,"\x00@@species",t->t);
            method(p,"get",1,(t,a,_)->{var m=thisMap(t,isSet,"get");var i=mapIndex(m,arg(a,0));return i<0?undef():m.values[i];});
            method(p,"has",1,(t,a,_)->mapIndex(thisMap(t,isSet,"has"),arg(a,0))>=0);
            if(isSet)method(p,"add",1,(t,a,_)->mapPut(thisMap(t,true,"add"),arg(a,0),arg(a,0)));
            else method(p,"set",2,(t,a,_)->mapPut(thisMap(t,false,"set"),arg(a,0),arg(a,1)));
            method(p,"delete",1,(t,a,_)->mapDelete(thisMap(t,isSet,"delete"),arg(a,0)));
            method(p,"clear",0,(t,_,_)->{var m=thisMap(t,isSet,"clear");for(i in 0...m.active.length)m.active[i]=false;MapIndex.clear(m);return undef();});
            method(p,"forEach",1,(t,a,_)->{var m=thisMap(t,isSet,"forEach");var f=callback(arg(a,0));var i=0;while(i<m.keys.length){if(m.active[i])call(f,arg(a,1),[m.values[i],m.keys[i],m]);i++;}return undef();});
            getter(p,"size",t->{var m=thisMap(t,isSet,"size");var count=0;for(v in m.active)if(v)count++;return count;});
            var iteratorProto=isSet?SetIteratorProto:MapIteratorProto;
            method(p,"keys",0,(t,_,_)->new JsIterator(iteratorProto,thisMap(t,isSet,"keys"),isSet?"values":"keys"));
            method(p,"entries",0,(t,_,_)->new JsIterator(iteratorProto,thisMap(t,isSet,"entries"),"entries"));
            var values=native("values",0,(t,_,_)->new JsIterator(iteratorProto,thisMap(t,isSet,"values"),"values"));
            p.setOwn("values",values,Attr.HIDDEN);
            if(isSet)p.setOwn("keys",values,Attr.HIDDEN);
            p.setOwn(Symbols.iterator,isSet?values:p.slots.get("entries"),Attr.HIDDEN);
            p.setOwn(Symbols.toStringTag,name,Attr.HIDDEN|Attr.READONLY);
            if(!isSet)method(c,"groupBy",2,(_,a,_)->groupBy(arg(a,0),arg(a,1),true));
        }
        // (weak collections hold their keys strongly)
        for(name in ["WeakMap","WeakSet"]) {
            var isSet=name=="WeakSet";var p=new JsObject(ObjectProto);
            function key(k:Dynamic):Dynamic {if(!isObject(k) && !Std.isOfType(k,Symbols.JsSymbol))error("TypeError","Invalid value used "+(isSet?"in weak set":"as weak map key"));return k;}
            method(p,"has",1,(t,a,_)->{var m=thisMap(t,isSet,"has",true);return isObject(arg(a,0)) && mapIndex(m,arg(a,0))>=0;});
            method(p,"delete",1,(t,a,_)->{var m=thisMap(t,isSet,"delete",true);return isObject(arg(a,0)) && mapDelete(m,arg(a,0));});
            if(isSet)method(p,"add",1,(t,a,_)->mapPut(thisMap(t,true,"add",true),key(arg(a,0)),arg(a,0)));
            else {
                method(p,"get",1,(t,a,_)->{var m=thisMap(t,false,"get",true);var i=isObject(arg(a,0))?mapIndex(m,arg(a,0)):-1;return i<0?undef():m.values[i];});
                method(p,"set",2,(t,a,_)->mapPut(thisMap(t,false,"set",true),key(arg(a,0)),arg(a,1)));
            }
            p.setOwn(Symbols.toStringTag,name,Attr.HIDDEN|Attr.READONLY);
            constructor(name,0,p,(_,a,nt)->{
                if(nt==undef())error("TypeError","Constructor "+name+" requires 'new'");
                var m=new JsMap(protoFrom(nt,p),isSet);m.weak=true;
                for(v in (arg(a,0)==undef() || arg(a,0)==null?[]:toList(arg(a,0))))if(isSet)mapPut(m,key(v),v);else mapPut(m,key(get(v,0)),get(v,1));
                return m;
            });
        }
    }

    public static function templateObject(cooked:Array<Dynamic>,raw:Array<Dynamic>):Dynamic {
        var r=array(raw);integrity(r,true);
        var a:JsArray=cast array(cooked);a.setOwn("raw",r,Attr.HIDDEN|Attr.READONLY|Attr.LOCKED);integrity(a,true);
        return a;
    }
    // structuredClone: plain data, arrays, Map/Set, Date, RegExp and errors; shared and cyclic references kept.
    static function clone(v:Dynamic,seen:haxe.ds.ObjectMap<Dynamic,Dynamic>):Dynamic {
        if(Std.isOfType(v,Symbols.JsSymbol))error("DataCloneError",Symbols.text(v)+" could not be cloned.");
        if(!isObject(v))return v;
        if(seen.exists(v))return seen.get(v);
        if(Std.isOfType(v,JsFunction))error("DataCloneError",Inspect.inspect(v)+" could not be cloned.");
        if(Std.isOfType(v,Dates.JsDate)){var d=Dates.make((v:Dates.JsDate).time);seen.set(v,d);return d;}
        if(Regex.isRegExp(v)){var r:Regex.JsRegExp=cast v;var c=Regex.compile(r.source,r.flags);seen.set(v,c);return c;}
        if(Std.isOfType(v,JsMap)) {
            var m:JsMap=cast v;var c=new JsMap(m.isSet?SetProto:MapProto,m.isSet);seen.set(v,c);
            for(i in 0...m.keys.length)if(m.active[i])mapPut(c,clone(m.keys[i],seen),clone(m.values[i],seen));
            return c;
        }
        if(Std.isOfType(v,JsArray)) {
            var a:JsArray=cast v;var c=new JsArray(ArrayProto);seen.set(v,c);c.length=a.length;
            for(k in keys(a))defineOwn(c,k,clone(get(a,k),seen));
            return c;
        }
        var o:JsObject=v;
        var c=Std.isOfType(v,JsError)?new JsError(o.proto):new JsObject(ObjectProto);seen.set(v,c);
        if(Std.isOfType(v,JsError))for(k in ["message","name","cause"])if(o.hasOwn(k))c.setOwn(k,clone(o.slots.get(k),seen),Attr.HIDDEN);
        for(k in keys(o))c.setOwn(k,clone(get(o,k),seen));
        return c;
    }
    // encodeURI(Component): UTF-8 escapes for characters outside the unreserved set.
    static function encodeUri(s:String,keep:String):String {
        var out=new StringBuf();var i=0;
        while(i<s.length) {
            var c=s.charCodeAt(i);
            if(c<128 && (c>=48&&c<=57 || c>=65&&c<=90 || c>=97&&c<=122 || keep.indexOf(String.fromCharCode(c))>=0)){out.addChar(c);i++;continue;}
            var cp=c;
            if(c>=0xdc00 && c<=0xdfff)error("URIError","URI malformed");
            if(c>=0xd800 && c<=0xdbff){var d=i+1<s.length?s.charCodeAt(i+1):0;if(d<0xdc00 || d>0xdfff)error("URIError","URI malformed");cp=(c-0xd800)*1024+(d-0xdc00)+0x10000;i++;}
            i++;
            var bytes=cp<0x80?[cp]:cp<0x800?[0xc0|(cp>>6),0x80|(cp&63)]:cp<0x10000?[0xe0|(cp>>12),0x80|((cp>>6)&63),0x80|(cp&63)]:[0xf0|(cp>>18),0x80|((cp>>12)&63),0x80|((cp>>6)&63),0x80|(cp&63)];
            for(b in bytes)out.add("%"+StringTools.hex(b,2));
        }
        return out.toString();
    }
    static function decodeUri(s:String,reserved:String):String {
        var out=new StringBuf();var i=0;
        function hexAt(k:Int):Int {if(k+2>=s.length+0 && k+2>s.length)return -1;var h=s.substr(k+1,2);if(h.length<2 || s.charAt(k)!="%")return -1;var v=0;for(j in 0...2){var c=h.charCodeAt(j);var d=c>=48&&c<=57?c-48:c>=65&&c<=70?c-55:c>=97&&c<=102?c-87:-1;if(d<0)return -1;v=v*16+d;}return v;}
        while(i<s.length) {
            var c=s.charAt(i);
            if(c!="%"){out.add(c);i++;continue;}
            var b=hexAt(i);if(b<0)error("URIError","URI malformed");
            if(b<0x80){var ch=String.fromCharCode(b);out.add(reserved.indexOf(ch)>=0?s.substr(i,3):ch);i+=3;continue;}
            var n=b>=0xf0?4:b>=0xe0?3:b>=0xc0?2:0;if(n==0)error("URIError","URI malformed");
            var cp=b&(0xff>>(n+1));var start=i;i+=3;
            for(_ in 1...n){var x=hexAt(i);if(x<0 || x&0xc0!=0x80)error("URIError","URI malformed");cp=(cp<<6)|(x&63);i+=3;}
            if(cp>0x10ffff || cp>=0xd800 && cp<=0xdfff || n==2 && cp<0x80 || n==3 && cp<0x800 || n==4 && cp<0x10000)error("URIError","URI malformed");
            if(cp<0x10000)out.addChar(cp);else{cp-=0x10000;out.addChar(0xd800+(cp>>10));out.addChar(0xdc00+(cp&1023));}
        }
        return out.toString();
    }
    // Globals: functions, Math, console, Reflect, globalThis and the Test262 harness.
    static function setupGlobals():Void {
        globals.set("undefined",undef());globals.set("NaN",Math.NaN);globals.set("Infinity",Math.POSITIVE_INFINITY);
        var number:JsObject=globals.get("Number");
        var parseIntFn=native("parseInt",2,(_,a,_)->Numbers.parseInteger(Seed.text(arg(a,0)),arg(a,1)));
        var parseFloatFn=native("parseFloat",1,(_,a,_)->Numbers.parseDecimalPrefix(Seed.text(arg(a,0))));
        globals.set("parseInt",parseIntFn);globals.set("parseFloat",parseFloatFn);
        number.setOwn("parseInt",parseIntFn,Attr.HIDDEN);number.setOwn("parseFloat",parseFloatFn,Attr.HIDDEN);
        globals.set("structuredClone",native("structuredClone",1,(_,a,_)->clone(arg(a,0),new haxe.ds.ObjectMap())));
        globals.set("encodeURIComponent",native("encodeURIComponent",1,(_,a,_)->encodeUri(Seed.text(arg(a,0)),"-_.!~*'()")));
        globals.set("encodeURI",native("encodeURI",1,(_,a,_)->encodeUri(Seed.text(arg(a,0)),"-_.!~*'();/?:@&=+$,#")));
        globals.set("decodeURIComponent",native("decodeURIComponent",1,(_,a,_)->decodeUri(Seed.text(arg(a,0)),"")));
        globals.set("decodeURI",native("decodeURI",1,(_,a,_)->decodeUri(Seed.text(arg(a,0)),";/?:@&=+$,#")));
        globals.set("isNaN",native("isNaN",1,(_,a,_)->Math.isNaN(Seed.numeric(arg(a,0)))));
        globals.set("isFinite",native("isFinite",1,(_,a,_)->Math.isFinite(Seed.numeric(arg(a,0)))));
        var math=new JsObject(ObjectProto);globals.set("Math",math);
        math.setOwn(Symbols.toStringTag,"Math",Attr.HIDDEN|Attr.READONLY);
        constant(math,"PI",Math.PI);constant(math,"E",Math.exp(1));constant(math,"LN2",Math.log(2));constant(math,"LN10",Math.log(10));
        constant(math,"LOG2E",1/Math.log(2));constant(math,"LOG10E",1/Math.log(10));constant(math,"SQRT2",Math.sqrt(2));constant(math,"SQRT1_2",Math.sqrt(0.5));
        for(name in ["abs","floor","ceil","trunc","round","sqrt","cbrt","sin","cos","tan","asin","acos","atan","exp","expm1","log","log1p","log2","log10","sign","fround","f16round","clz32","sinh","cosh","tanh","asinh","acosh","atanh"])
            method(math,name,1,(_,a,_)->Numbers.math(name,Seed.numeric(arg(a,0)),0));
        for(name in ["pow","atan2","imul"])method(math,name,2,(_,a,_)->name=="imul"?toInt32(arg(a,0))*toInt32(arg(a,1)):Numbers.math(name,Seed.numeric(arg(a,0)),Seed.numeric(arg(a,1))));
        method(math,"random",0,(_,_,_)->Math.random());
        for(name in ["min","max","hypot"])method(math,name,2,(_,a,_)->{
            var values=[for(v in a)Seed.numeric(v)];
            if(name=="hypot"){var sum=0.0;var inf=false;var nan=false;for(n in values){if(!Math.isFinite(n) && !Math.isNaN(n))inf=true;if(Math.isNaN(n))nan=true;sum+=n*n;}return inf?Math.POSITIVE_INFINITY:nan?Math.NaN:Math.sqrt(sum);}
            var result=name=="min"?Math.POSITIVE_INFINITY:Math.NEGATIVE_INFINITY;
            for(n in values){if(Math.isNaN(n))return Math.NaN;if(name=="min"?(n<result || n==0 && result==0 && 1/n<0):(n>result || n==0 && result==0 && 1/n>0))result=n;}
            return result;
        });
        var console=new JsObject(ObjectProto);globals.set("console",console);
        for(name in ["log","info","debug","error","warn","trace"])method(console,name,0,(_,a,_)->{
            var line=Inspect.format(a);
            if(name=="error" || name=="warn" || name=="trace")Sys.stderr().writeString(line+"\n");else Seed.print(line+"\n");
            return undef();
        });
        var reflect=new JsObject(ObjectProto);globals.set("Reflect",reflect);
        reflect.setOwn(Symbols.toStringTag,"Reflect",Attr.HIDDEN|Attr.READONLY);
        method(reflect,"ownKeys",1,(_,a,_)->{var o=arg(a,0);if(!isObject(o))error("TypeError","Reflect.ownKeys called on non-object");return array([for(k in ownPropertyKeys(o))Symbols.isSymbolKey(k) && Symbols.fromKey(k)!=null?(Symbols.fromKey(k):Dynamic):k]);});
        method(reflect,"has",2,(_,a,_)->has(arg(a,0),arg(a,1)));
        method(reflect,"get",2,(_,a,_)->{var o=arg(a,0);if(!isObject(o))error("TypeError","Reflect.get called on non-object");return getKey(o,key(arg(a,1)),a.length>2?a[2]:o);});
        method(reflect,"set",3,(_,a,_)->{try{put(arg(a,0),arg(a,1),arg(a,2));return true;}catch(e:Dynamic){return false;}});
        method(reflect,"apply",3,(_,a,_)->call(arg(a,0),arg(a,1),arrayLikeList(arg(a,2))));
        method(reflect,"construct",2,(_,a,_)->construct(arg(a,0),arrayLikeList(arg(a,1)),a.length>2?a[2]:arg(a,0)));
        method(reflect,"getPrototypeOf",1,(_,a,_)->(arg(a,0):JsObject).proto);
        method(reflect,"setPrototypeOf",2,(_,a,_)->{setPrototype(arg(a,0),arg(a,1));return true;});
        method(reflect,"defineProperty",3,(_,a,_)->{try{defineProperty(arg(a,0),key(arg(a,1)),arg(a,2));return true;}catch(e:Dynamic){return false;}});
        method(reflect,"deleteProperty",2,(_,a,_)->{try{return remove(arg(a,0),arg(a,1));}catch(e:Dynamic){return false;}});
        method(reflect,"getOwnPropertyDescriptor",2,(_,a,_)->descriptor(arg(a,0),key(arg(a,1))));
        method(reflect,"isExtensible",1,(_,a,_)->(arg(a,0):JsObject).extensible);
        method(reflect,"preventExtensions",1,(_,a,_)->{(arg(a,0):JsObject).extensible=false;return true;});
        // Test262 harness (assert.js, sta.js, compareArray.js)
        var assert=native("assert",2,(_,a,_)->{if(arg(a,0)!=true)error("Test262Error",arg(a,1)==undef()?"Expected true but got "+Seed.text(arg(a,0)):Seed.text(arg(a,1)));return undef();});
        globals.set("assert",assert);
        method(assert,"sameValue",2,(_,a,_)->{if(!sameValue(arg(a,0),arg(a,1)))error("Test262Error",(arg(a,2)==undef()?"":Seed.text(arg(a,2))+" ")+"Expected SameValue("+Inspect.format([arg(a,0)])+", "+Inspect.format([arg(a,1)])+") to be true");return undef();});
        method(assert,"notSameValue",2,(_,a,_)->{if(sameValue(arg(a,0),arg(a,1)))error("Test262Error",(arg(a,2)==undef()?"":Seed.text(arg(a,2))+" ")+"Expected SameValue to be false");return undef();});
        method(assert,"throws",2,(_,a,_)->{
            var expected=arg(a,0);var f=callback(arg(a,1));var caught=false;
            try call(f,undef(),[]) catch(e:Dynamic){caught=true;if(!isObject(e) || get(e,"constructor")!=expected)error("Test262Error","Expected a "+Seed.text(get(expected,"name"))+" to be thrown but got "+(isObject(e)?Seed.text(get(get(e,"constructor"),"name")):Seed.text(e)));}
            if(!caught)error("Test262Error","Expected a "+Seed.text(get(expected,"name"))+" to be thrown but no exception was thrown at all");
            return undef();
        });
        method(assert,"compareArray",2,(_,a,_)->{
            var x=arg(a,0),y=arg(a,1);var same=lengthOf(x)==lengthOf(y);var i:Float=0;while(same && i<lengthOf(x)){if(!sameValue(get(x,i),get(y,i)))same=false;i++;}
            if(!same)error("Test262Error","Actual "+Inspect.format([x])+" and expected "+Inspect.format([y])+" should have the same contents. "+(arg(a,2)==undef()?"":Seed.text(arg(a,2))));return undef();
        });
        globals.set("$EXPECT_ASYNC",native("$EXPECT_ASYNC",0,(_,_,_)->{asyncExpected=true;asyncDone=0;return undef();}));
        globals.set("$DONE",native("$DONE",1,(_,a,_)->{if(arg(a,0)!=undef())throw arg(a,0);if(++asyncDone!=1)error("Test262Error","$DONE called more than once");return undef();}));
        globals.set("$ERROR",native("$ERROR",1,(_,a,_)->error("Test262Error",Seed.text(arg(a,0)))));
        globals.set("$DONOTEVALUATE",native("$DONOTEVALUATE",0,(_,_,_)->error("Test262Error","Test262: This statement should not be evaluated.")));
        var harness=new JsObject(ObjectProto);method(harness,"detachArrayBuffer",1,(_,a,_)->Buffers.detach(arg(a,0)));globals.set("$262",harness);
        var globalObject=new JsObject(ObjectProto);
        globals.set("globalThis",globalObject);
        for(name=>v in globals)if(name!="globalThis")globalObject.setOwn(name,v,Attr.HIDDEN);
    }
}
// (Map and Set lookup indexes, created on first use)
class MapIndex {
    public static function strings(m:JsMap):Map<String,Int> {if(m.primitiveIndex==null)m.primitiveIndex=[];return m.primitiveIndex;}
    public static function objects(m:JsMap):haxe.ds.ObjectMap<Dynamic,Int> {if(m.objectIndex==null)m.objectIndex=new haxe.ds.ObjectMap();return m.objectIndex;}
    public static function clear(m:JsMap):Void {m.primitiveIndex=null;m.objectIndex=null;}
}
