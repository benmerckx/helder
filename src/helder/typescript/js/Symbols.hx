package helder.typescript.js;
import helder.typescript.js.Values;

// Symbols are primitives (typeof "symbol"). A symbol-keyed property is stored
// under the symbol's internal key, a string no JavaScript string key can
// collide with in practice (it starts with NUL and "@"); string-key
// enumeration skips such keys.
class JsSymbol {
    public var description:Dynamic;
    public var key:String;
    public function new(description:Dynamic,key:String) {this.description=description;this.key=key;}
}
class Symbols {
    static var serial=0;
    public static var registry:Map<String,JsSymbol>=[];
    public static var byKey:Map<String,JsSymbol>=[];
    public static var iterator(get,never):String;
    public static var asyncIterator(get,never):String;
    public static var hasInstance(get,never):String;
    public static var toPrimitive(get,never):String;
    public static var toStringTag(get,never):String;
    static inline function get_iterator() return "\x00@@iterator";
    static inline function get_asyncIterator() return "\x00@@asyncIterator";
    static inline function get_hasInstance() return "\x00@@hasInstance";
    static inline function get_toPrimitive() return "\x00@@toPrimitive";
    static inline function get_toStringTag() return "\x00@@toStringTag";
    public static function isSymbolKey(k:String):Bool return k.length>1 && k.charCodeAt(0)==0 && k.charCodeAt(1)==64;
    public static function create(description:Dynamic):JsSymbol {
        var s=new JsSymbol(description,"\x00@"+(serial++)+":"+(description==Seed.undefinedValue?"":Std.string(description)));
        byKey.set(s.key,s);return s;
    }
    public static function wellKnown(name:String):JsSymbol {
        var k="\x00@@"+name;
        if(!byKey.exists(k))byKey.set(k,new JsSymbol("Symbol."+name,k));
        return byKey.get(k);
    }
    public static function symbolFor(k:String):JsSymbol {
        if(!registry.exists(k))registry.set(k,create(k));
        return registry.get(k);
    }
    public static function fromKey(k:String):JsSymbol return byKey.get(k);
    // (a property key as a function name: symbols as "[description]")
    public static function functionName(k:String):String {
        if(!isSymbolKey(k))return k;
        var s=byKey.get(k);if(s==null && StringTools.startsWith(k,"\x00@@"))s=wellKnown(k.substr(3));return s==null || s.description==Seed.undefinedValue?"":"["+Std.string(s.description)+"]";
    }
    public static function text(s:JsSymbol):String return "Symbol("+(s.description==Seed.undefinedValue?"":Std.string(s.description))+")";
}
