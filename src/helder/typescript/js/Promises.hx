package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;
import helder.typescript.js.Async.JsGenerator;

class JsPromise extends JsObject {
    public var state=0; // 0 pending, 1 fulfilled, 2 rejected
    public var value:Dynamic=null;
    public var reactions:Array<Reaction>=[];
    public var handled=false;
    override public function tag():String return "Promise";
}
// A then() registration (host callbacks are wrapped as native functions: see host).
class Reaction {
    public var onFulfilled:Dynamic;
    public var onRejected:Dynamic;
    public var child:JsPromise;
    public function new(f:Dynamic,r:Dynamic,child:JsPromise) {onFulfilled=f;onRejected=r;this.child=child;}
}
class JsAsyncGenerator extends JsGenerator {
    public var requests:Array<{mode:Int,value:Dynamic,promise:JsPromise}>=[];
    public var busy=false;
    override public function tag():String return "AsyncGenerator";
}
class Timer {
    public var id:Int;
    public var due:Float;
    public var seq:Int;
    public var callback:Dynamic;
    public var args:Array<Dynamic>;
    public var interval:Float;
    public function new() {}
}
// Promises, async functions, the microtask queue, timers and the event loop
// (Node's order: microtasks after each callback, then due timers, then immediates).
class Promises {
    public static var PromiseProto:JsObject;
    static var PromiseCtor:JsFunction;
    static var jobs:Array<()->Void>=[];
    static var timers:Array<Timer>=[];
    static var immediates:Array<Timer>=[];
    static var timerSeq=0;
    static var unhandled:Array<JsPromise>=[];
    static var start:Float=0;
    // An embedding host can request a microtask checkpoint on its own loop.
    // The standalone JS runner leaves this unset and keeps its existing loop.
    public static var requestCheckpoint:(()->Void)=null;
    public static function enqueue(job:()->Void):Void {
        jobs.push(job);
        if(requestCheckpoint!=null)requestCheckpoint();
    }

    public static function setup():Void {
        start=Sys.time();setupAsyncGenerators();
        PromiseProto=new JsObject(Builtins.ObjectProto);
        PromiseProto.setOwn(Symbols.toStringTag,"Promise",Attr.HIDDEN|Attr.READONLY);
        PromiseCtor=Builtins.nativeFunction("Promise",1,(_,a,nt)->{
            if(nt==undef())error("TypeError","Promise constructor cannot be invoked without 'new'");
            var executor=arg(a,0);
            if(!isCallable(executor))error("TypeError","Promise resolver "+Inspect.inspect(executor)+" is not a function");
            var p=create(protoFrom(nt,PromiseProto));var fns=resolvingFunctions(p);
            try call(executor,undef(),fns) catch(e:Dynamic) call(fns[1],undef(),[e]);
            return p;
        },true);
        PromiseCtor.setOwn("prototype",PromiseProto,Attr.HIDDEN|Attr.READONLY|Attr.LOCKED);
        PromiseProto.setOwn("constructor",PromiseCtor,Attr.HIDDEN);
        Builtins.globals.set("Promise",PromiseCtor);
        function method(target:JsObject,name:String,arity:Int,fn:(Dynamic,Array<Dynamic>,Dynamic)->Dynamic) target.setOwn(name,Builtins.nativeFunction(name,arity,fn),Attr.HIDDEN);
        method(PromiseProto,"then",2,(t,a,_)->chain(thisPromise(t,"then"),arg(a,0),arg(a,1),species(t)));
        method(PromiseProto,"catch",1,(t,a,_)->callMethod(t,"then",[undef(),arg(a,0)]));
        method(PromiseProto,"finally",1,(t,a,_)->{
            if(!isObject(t))return error("TypeError","Promise.finally receiver must be an object");
            var ctor=species(t),f=arg(a,0);
            if(!isCallable(f))return callMethod(t,"then",[f,f]);
            var onF=Builtins.nativeFunction("",1,(_,v,_)->{var r=call(f,undef(),[]);return callMethod(resolveFor(ctor,r),"then",[Builtins.nativeFunction("",0,(_,_,_)->arg(v,0))]);});
            var onR=Builtins.nativeFunction("",1,(_,v,_)->{var r=call(f,undef(),[]);return callMethod(resolveFor(ctor,r),"then",[Builtins.nativeFunction("",0,(_,_,_)->throw arg(v,0))]);});
            return callMethod(t,"then",[onF,onR]);
        });
        method(PromiseCtor,"resolve",1,(t,a,_)->resolveFor(t,arg(a,0)));
        method(PromiseCtor,"reject",1,(t,a,_)->{var cap=capability(t);call(cap.reject,undef(),[arg(a,0)]);return cap.promise;});
        method(PromiseCtor,"withResolvers",0,(t,_,_)->{var cap=capability(t);return object(["promise","resolve","reject"],[cap.promise,cap.resolve,cap.reject]);});
        method(PromiseCtor,"try",1,(t,a,_)->{
            if(!isObject(t))return error("TypeError","Promise.try receiver must be an object");
            var value:Dynamic;
            try value=call(arg(a,0),undef(),a.slice(1)) catch(e:Dynamic){var cap=capability(t);call(cap.reject,undef(),[e]);return cap.promise;}
            return resolveFor(t,value);
        });
        PromiseCtor.setOwn("\x00@@species",new Accessor(Builtins.nativeFunction("get [Symbol.species]",0,(t,_,_)->t),null),Attr.HIDDEN);
        for(name in ["all","allSettled","any","race"]) method(PromiseCtor,name,1,(_,a,_)->combinator(name,toList(arg(a,0))));
        method(Builtins.globals.get("globalThis"),"queueMicrotask",1,(_,a,_)->{var f=arg(a,0);if(!isCallable(f))error("TypeError","The \"callback\" argument must be of type function. Received "+Inspect.inspect(f));enqueue(()->call(f,undef(),[]));return undef();});
        var global:JsObject=Builtins.globals.get("globalThis");
        Builtins.globals.set("queueMicrotask",global.slots.get("queueMicrotask"));
        function timerFunction(name:String,repeat:Bool,immediate:Bool) {
            var f=Builtins.nativeFunction(name,immediate?1:2,(_,a,_)->{
                var cb=arg(a,0);if(!isCallable(cb))error("TypeError","The \"callback\" argument must be of type function. Received "+Inspect.inspect(cb));
                var t=new Timer();t.id=++timerSeq;t.seq=t.id;t.callback=cb;t.args=a.slice(immediate?1:2);
                var delay=immediate?0:Seed.numeric(arg(a,1));if(!(delay>=1 && delay<=2147483647))delay=1;
                t.interval=repeat?delay:-1;t.due=now()+delay;
                if(immediate)immediates.push(t);else timers.push(t);
                return t.id;
            });
            Builtins.globals.set(name,f);global.setOwn(name,f,Attr.HIDDEN);
        }
        timerFunction("setTimeout",false,false);timerFunction("setInterval",true,false);timerFunction("setImmediate",false,true);
        for(name in ["clearTimeout","clearInterval","clearImmediate"]) {
            var f=Builtins.nativeFunction(name,1,(_,a,_)->{
                var id=Seed.numeric(arg(a,0));
                timers=timers.filter(t->t.id!=id);immediates=immediates.filter(t->t.id!=id);return undef();
            });
            Builtins.globals.set(name,f);global.setOwn(name,f,Attr.HIDDEN);
        }
    }
    static function capability(ctor:Dynamic):{promise:Dynamic,resolve:Dynamic,reject:Dynamic} {
        if(!isConstructor(ctor))return error("TypeError","Promise constructor is not a constructor");
        var resolveFn:Dynamic=undef(),rejectFn:Dynamic=undef();
        var executor=Builtins.nativeFunction("",2,(_,a,_)->{
            if(resolveFn!=undef() || rejectFn!=undef())return error("TypeError","Promise executor called twice");
            resolveFn=arg(a,0);rejectFn=arg(a,1);return undef();
        });
        var promise=construct(ctor,[executor],ctor);
        if(!isCallable(resolveFn) || !isCallable(rejectFn))return error("TypeError","Promise resolve/reject must be callable");
        return {promise:promise,resolve:resolveFn,reject:rejectFn};
    }
    static function species(o:Dynamic):Dynamic {
        var ctor=get(o,"constructor");if(ctor==undef())return PromiseCtor;
        if(!isObject(ctor))return error("TypeError","Promise constructor must be an object");
        var chosen=get(ctor,"\x00@@species");if(chosen==null || chosen==undef())return PromiseCtor;
        if(!isConstructor(chosen))return error("TypeError","Promise species is not a constructor");
        return chosen;
    }
    static function resolveFor(ctor:Dynamic,v:Dynamic):Dynamic {
        if(!isObject(ctor))return error("TypeError","Promise.resolve receiver must be an object");
        if(Std.isOfType(v,JsPromise) && get(v,"constructor")==ctor)return v;
        var cap=capability(ctor);call(cap.resolve,undef(),[v]);return cap.promise;
    }
    static function chain(p:JsPromise,f:Dynamic,r:Dynamic,ctor:Dynamic):Dynamic {
        var cap=capability(ctor);
        function handle(handler:Dynamic,rejected:Bool,v:Dynamic):Void {
            if(!isCallable(handler)){call(rejected?cap.reject:cap.resolve,undef(),[v]);return;}
            var result:Dynamic;
            try result=call(handler,undef(),[v]) catch(e:Dynamic){call(cap.reject,undef(),[e]);return;}
            call(cap.resolve,undef(),[result]);
        }
        then(p,host(v->handle(f,false,v)),host(v->handle(r,true,v)),null);
        return cap.promise;
    }
    public static function now():Float return (Sys.time()-start)*1000;
    static function create(proto:JsObject):JsPromise return new JsPromise(proto);
    static function thisPromise(t:Dynamic,name:String):JsPromise {
        if(!Std.isOfType(t,JsPromise))error("TypeError","Method Promise.prototype."+name+" called on incompatible receiver "+Inspect.inspect(t));
        return t;
    }
    public static function resolved(v:Dynamic):JsPromise {
        if(Std.isOfType(v,JsPromise) && (v:JsPromise).proto==PromiseProto)return v;
        var p=create(PromiseProto);resolve(p,v);return p;
    }
    static function resolvingFunctions(p:JsPromise):Array<Dynamic> {
        var done=false;
        return [
            Builtins.nativeFunction("",1,(_,a,_)->{if(!done){done=true;resolve(p,arg(a,0));}return undef();}),
            Builtins.nativeFunction("",1,(_,a,_)->{if(!done){done=true;reject(p,arg(a,0));}return undef();})
        ];
    }
    // The promise resolution procedure: thenables are adopted in a job.
    public static function resolve(p:JsPromise,v:Dynamic):Void {
        if(v==p){reject(p,Builtins.makeError("TypeError","Chaining cycle detected for promise #<Promise>"));return;}
        if(!isObject(v)){settle(p,1,v);return;}
        var thenFn:Dynamic;
        try thenFn=get(v,"then") catch(e:Dynamic){reject(p,e);return;}
        if(!isCallable(thenFn)){settle(p,1,v);return;}
        enqueue(()->{
            var fns=resolvingFunctions(p);
            try call(thenFn,v,fns) catch(e:Dynamic) call(fns[1],undef(),[e]);
        });
    }
    public static function reject(p:JsPromise,e:Dynamic):Void {
        settle(p,2,e);
        if(!p.handled)unhandled.push(p);
        if(requestCheckpoint!=null)requestCheckpoint();
    }
    static function settle(p:JsPromise,state:Int,v:Dynamic):Void {
        if(p.state!=0)return;
        p.state=state;p.value=v;
        for(r in p.reactions)schedule(p,r);
        p.reactions=[];
    }
    static function then(p:JsPromise,onFulfilled:Dynamic,onRejected:Dynamic,child:JsPromise):JsPromise {
        var r=new Reaction(onFulfilled,onRejected,child);
        if(p.state==0)p.reactions.push(r);else schedule(p,r);
        if(!p.handled){p.handled=true;unhandled.remove(p);}
        return child;
    }
    static function schedule(p:JsPromise,r:Reaction):Void {
        var state=p.state,value=p.value;
        enqueue(()->{
            var handler=state==1?r.onFulfilled:r.onRejected;
            if(handler==null){if(r.child!=null){if(state==1)resolve(r.child,value);else reject(r.child,value);}return;}
            try {
                var result=call(handler,undef(),[value]);
                if(r.child!=null)resolve(r.child,result);
            }
            catch(e:Dynamic){if(r.child!=null)reject(r.child,e);else throw e;}
        });
    }
    static function host(f:Dynamic->Void):Dynamic return Builtins.nativeFunction("",1,(_,a,_)->{f(arg(a,0));return undef();});
    static function combinator(name:String,items:Array<Dynamic>):Dynamic {
        var p=create(PromiseProto);var results:Array<Dynamic>=[for(_ in items)undef()];var remaining=items.length;
        if(remaining==0){if(name=="any")reject(p,aggregate([]));else if(name!="race")resolve(p,array([]));return p;}
        for(i in 0...items.length) {
            var item=resolved(items[i]);
            then(item,host(v->{
                switch(name) {
                    case "race"|"any":resolve(p,v);
                    case "allSettled":results[i]=object(["status","value"],["fulfilled",v]);if(--remaining==0)resolve(p,array(results));
                    case _:results[i]=v;if(--remaining==0)resolve(p,array(results));
                }
            }),host(e->{
                switch(name) {
                    case "allSettled":results[i]=object(["status","reason"],["rejected",e]);if(--remaining==0)resolve(p,array(results));
                    case "any":results[i]=e;if(--remaining==0)reject(p,aggregate(results));
                    case _:reject(p,e);
                }
            }),null);
        }
        return p;
    }
    static function aggregate(errors:Array<Dynamic>):Dynamic {
        var c=Builtins.global("AggregateError");return construct(c,[array(errors),"All promises were rejected"],c);
    }
    // Async generators: requests (next/throw/return) queue up; each runs the
    // body through its awaits until a yield or the end settles its promise.
    public static var AsyncGeneratorProto:JsObject;
    static function setupAsyncGenerators():Void {
        var asyncIteratorProto=new JsObject(Builtins.ObjectProto);
        asyncIteratorProto.setOwn(Symbols.asyncIterator,Builtins.nativeFunction("[Symbol.asyncIterator]",0,(t,_,_)->t),Attr.HIDDEN);
        AsyncGeneratorProto=new JsObject(asyncIteratorProto);
        AsyncGeneratorProto.setOwn(Symbols.toStringTag,"AsyncGenerator",Attr.HIDDEN|Attr.READONLY);
        for(name in ["next","throw","return"]) {
            var mode=name=="next"?0:name=="throw"?1:2;
            AsyncGeneratorProto.setOwn(name,Builtins.nativeFunction(name,1,(t,a,_)->{
                var p=create(PromiseProto);
                if(!Std.isOfType(t,JsAsyncGenerator)){reject(p,Builtins.makeError("TypeError",name+" method called on incompatible receiver "+Seed.text(t)));return p;}
                var g:JsAsyncGenerator=t;g.requests.push({mode:mode,value:arg(a,0),promise:p});
                if(!g.busy)serve(g);
                return p;
            }),Attr.HIDDEN);
        }
    }
    public static function asyncGenerator(step:Dynamic):Dynamic return new JsAsyncGenerator(AsyncGeneratorProto,step);
    static function serve(g:JsAsyncGenerator):Void {
        if(g.requests.length==0){g.busy=false;return;}
        g.busy=true;var request=g.requests[0];
        function finish(settle:JsPromise->Void) {g.requests.shift();settle(request.promise);serve(g);}
        function run(sent:Dynamic,mode:Int):Void {
            var r:Dynamic;
            try r=Async.resume(g,sent,mode) catch(e:Dynamic){finish(p->reject(p,e));return;}
            var v=get(r,"value");
            if(!Seed.truth(get(r,"done")) && g.awaiting){then(resolved(v),host(x->run(x,0)),host(e->run(e,1)),null);return;}
            finish(p->resolve(p,r));
        }
        // (return() on a finished generator awaits its value)
        if(g.finished && request.mode==2){then(resolved(request.value),host(x->finish(p->resolve(p,object(["value","done"],[x,true])))),host(e->finish(p->reject(p,e))),null);return;}
        run(request.value,request.mode);
    }
    // for await: an async iterator, or a sync one whose values are awaited.
    public static function asyncIterator(o:Dynamic):Dynamic {
        var method=o==null || o==undef()?undef():getKey(o,Symbols.asyncIterator,o);
        if(method!=undef() && method!=null)return call(method,o,[]);
        var it=iterator(o);
        var wrapper=new JsObject(Builtins.ObjectProto);
        wrapper.setOwn("next",Builtins.nativeFunction("next",1,(_,_,_)->{
            var r=next(it);var p=create(PromiseProto);
            var done=Seed.truth(get(r,"done"));
            then(resolved(get(r,"value")),host(v->resolve(p,object(["value","done"],[v,done]))),host(e->reject(p,e)),null);
            return p;
        }),Attr.HIDDEN);
        return wrapper;
    }
    // An async function call: runs its body to the first await synchronously.
    public static function async(step:Dynamic):Dynamic {
        var p=create(PromiseProto);var g:JsGenerator=cast Async.generator(step);
        function run(sent:Dynamic,mode:Int):Void {
            var r:Dynamic;
            try r=Async.resume(g,sent,mode) catch(e:Dynamic){reject(p,e);return;}
            var v=get(r,"value");
            if(Seed.truth(get(r,"done"))){resolve(p,v);return;}
            then(resolved(v),host(x->run(x,0)),host(e->run(e,1)),null);
        }
        run(undef(),0);
        return p;
    }
    public static function drain():Void {
        var i=0;
        while(i<jobs.length){var job=jobs[i++];job();if(i>4096){jobs=jobs.slice(i);i=0;}}
        jobs=[];
        if(unhandled.length>0) {
            var e=unhandled[0].value;
            var text=Std.isOfType(e,JsError)?Builtins.errorText(e):"[UnhandledPromiseRejection: This error originated either by throwing inside of an async function without a catch block, or by rejecting a promise which was not handled with .catch(). The promise rejected with the reason \""+Inspect.inspect(e)+"\".] {\n  code: 'ERR_UNHANDLED_REJECTION'\n}";
            Sys.stderr().writeString("Uncaught "+text+"\n");Sys.exit(1);
        }
    }
    public static function runEventLoop():Void {
        drain();
        // (the first turn starts at least a millisecond after startup, as node's does)
        var first=true;
        while(timers.length>0 || immediates.length>0) {
            // (timers phase: those due, in order)
            var t=now()+(first?1:0);first=false;
            var due=[for(x in timers)if(x.due<=t)x];
            due.sort((a,b)->a.due<b.due?-1:a.due>b.due?1:a.seq-b.seq);
            for(x in due) {
                if(timers.indexOf(x)<0)continue;
                timers.remove(x);
                if(x.interval>=0){x.due=Math.max(now(),x.due)+x.interval;x.seq=++timerSeq;timers.push(x);}
                call(x.callback,undef(),x.args);drain();
            }
            // (check phase: immediates queued before it started)
            var batch=immediates;immediates=[];
            for(x in batch){call(x.callback,undef(),x.args);drain();}
            if(immediates.length==0 && timers.length>0 && due.length==0) {
                var next=timers[0].due;for(x in timers)if(x.due<next)next=x.due;
                var wait=next-now();if(wait>0)Sys.sleep(wait/1000);
            }
        }
    }
}
