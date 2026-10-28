package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;

// JSON.parse (key order kept, revivers) and JSON.stringify (replacers, indentation, toJSON).
class Json {
    public static function setup():Void {
        var json=new JsObject(Builtins.ObjectProto);
        json.setOwn(Symbols.toStringTag,"JSON",Attr.HIDDEN|Attr.READONLY);
        json.setOwn("parse",Builtins.nativeFunction("parse",2,(_,a,_)->{
            var value=new Json(Seed.text(arg(a,0))).document();
            var reviver=arg(a,1);
            if(!isCallable(reviver))return value;
            var root=object([""],[value]);
            return revive(root,"",reviver);
        }),Attr.HIDDEN);
        json.setOwn("stringify",Builtins.nativeFunction("stringify",3,(_,a,_)->stringify(arg(a,0),arg(a,1),arg(a,2))),Attr.HIDDEN);
        RawJson.setup(json);
        Builtins.globals.set("JSON",json);
    }
    static function revive(holder:Dynamic,k:String,reviver:Dynamic):Dynamic {
        var v=get(holder,k);
        if(isObject(v)) {
            var names:Array<String>=Std.isOfType(v,JsArray)?[for(i in 0...Std.int((v:JsArray).length))Std.string(i)]:keys(v);
            for(name in names){var r=revive(v,name,reviver);if(r==undef())remove(v,name);else defineOwn(v,name,r);}
        }
        return call(reviver,holder,[k,v]);
    }

    var s:String;
    var i=0;
    function new(s:String) this.s=s;
    function fail():Dynamic {
        return error("SyntaxError",i>=s.length?"Unexpected end of JSON input":"Unexpected token '"+s.charAt(i)+"', \""+(s.length>30?s.substr(0,30)+"\"... ":s+"\" ")+"is not valid JSON");
    }
    function space() while(i<s.length){var c=s.charCodeAt(i);if(c==32||c==9||c==10||c==13)i++;else break;}
    function document():Dynamic {space();var v=value();space();if(i<s.length)fail();return v;}
    function value():Dynamic {
        if(i>=s.length)return fail();
        var c=s.charAt(i);
        switch(c) {
            case "{":
                i++;var o=new JsObject(Builtins.ObjectProto);space();
                if(s.charAt(i)=="}"){i++;return o;}
                while(true){space();if(s.charAt(i)!="\"")fail();var k=string();space();if(s.charAt(i)!=":")fail();i++;space();defineOwn(o,k,value());space();var d=s.charAt(i++);if(d=="}")return o;if(d!=","){i--;fail();}}
            case "[":
                i++;var items:Array<Dynamic>=[];space();
                if(s.charAt(i)=="]"){i++;return array(items);}
                while(true){space();items.push(value());space();var d=s.charAt(i++);if(d=="]")return array(items);if(d!=","){i--;fail();}}
            case "\"":return string();
            case "t":if(s.substr(i,4)=="true"){i+=4;return true;}return fail();
            case "f":if(s.substr(i,5)=="false"){i+=5;return false;}return fail();
            case "n":if(s.substr(i,4)=="null"){i+=4;return null;}return fail();
            case _:
                var start=i;if(s.charAt(i)=="-")i++;
                if(s.charAt(i)=="0")i++;else if(digits()==0)return fail();
                if(s.charAt(i)=="."){i++;if(digits()==0)return fail();}
                if(s.charAt(i)=="e" || s.charAt(i)=="E"){i++;if(s.charAt(i)=="+" || s.charAt(i)=="-")i++;if(digits()==0)return fail();}
                return Std.parseFloat(s.substring(start,i));
        }
    }
    function digits():Int {var n=0;while(i<s.length && s.charCodeAt(i)>=48 && s.charCodeAt(i)<=57){i++;n++;}return n;}
    function string():String {
        i++;var b=new StringBuf();
        while(true) {
            if(i>=s.length)fail();
            var c=s.charCodeAt(i++);
            if(c==34)return b.toString();
            if(c<32){i--;fail();}
            if(c!=92){b.addChar(c);continue;}
            var e=s.charAt(i++);
            switch(e) {
                case "\"":b.add("\"");case "\\":b.add("\\");case "/":b.add("/");case "b":b.addChar(8);case "f":b.addChar(12);case "n":b.add("\n");case "r":b.add("\r");case "t":b.add("\t");
                case "u":
                    var code=0;
                    for(j in 0...4){var c=i+j<s.length?s.charCodeAt(i+j):0;var d=c>=48&&c<=57?c-48:c>=65&&c<=70?c-55:c>=97&&c<=102?c-87:-1;if(d<0){i--;fail();}code=code*16+d;}
                    b.addChar(code);i+=4;
                case _:i--;fail();
            }
        }
    }

    public static function quote(s:String):String {
        var b=new StringBuf();b.add("\"");
        for(j in 0...s.length) {
            var c=s.charCodeAt(j);
            switch(c) {
                case 34:b.add("\\\"");case 92:b.add("\\\\");case 8:b.add("\\b");case 12:b.add("\\f");case 10:b.add("\\n");case 13:b.add("\\r");case 9:b.add("\\t");
                case _:
                    var lone=c>=0xd800 && c<=0xdfff && !(c<=0xdbff && j+1<s.length && s.charCodeAt(j+1)>=0xdc00 && s.charCodeAt(j+1)<=0xdfff) && !(c>=0xdc00 && j>0 && s.charCodeAt(j-1)>=0xd800 && s.charCodeAt(j-1)<=0xdbff);
                    if(c<32 || lone)b.add("\\u"+StringTools.hex(c,4).toLowerCase());else b.addChar(c);
            }
        }
        b.add("\"");return b.toString();
    }
    static function stringify(value:Dynamic,replacer:Dynamic,spaceArg:Dynamic):Dynamic {
        var replacerFn=isCallable(replacer)?replacer:null;
        var allowed:Array<String>=null;
        if(replacerFn==null && Std.isOfType(replacer,JsArray)) {
            allowed=[];
            for(v in toList(replacer)){var item:Dynamic=null;if(Std.isOfType(v,String))item=v;else if(isNumber(v))item=Seed.numberText(v);else if(isObject(v) && (v:JsObject).hasOwn("\x00@primitive"))item=Seed.text(v);if(item!=null && allowed.indexOf(item)<0)allowed.push(item);}
        }
        if(isObject(spaceArg) && (spaceArg:JsObject).hasOwn("\x00@primitive"))spaceArg=(spaceArg:JsObject).slots.get("\x00@primitive");
        var gap="";
        if(isNumber(spaceArg)){var n=Std.int(Math.min(10,Math.max(0,toIntegerOrInfinity(spaceArg))));gap=StringTools.lpad(""," ",n);}
        else if(Std.isOfType(spaceArg,String))gap=(spaceArg:String).substr(0,10);
        var stack:Array<Dynamic>=[];
        function serialize(holder:Dynamic,k:String,indent:String):Dynamic {
            var v:Dynamic=get(holder,k);
            if(isObject(v) || Std.isOfType(v,String) || isNumber(v)) {
                var toJSON=getKey(v,"toJSON",v);
                if(isCallable(toJSON))v=call(toJSON,v,[k]);
            }
            if(replacerFn!=null)v=call(replacerFn,holder,[k,v]);
            if(isObject(v) && (v:JsObject).hasOwn("\x00@primitive"))v=(v:JsObject).slots.get("\x00@primitive");
            if(Std.isOfType(v,RawJson.JsRawJson))return (v:RawJson.JsRawJson).raw;
            if(v==null)return "null";
            if(Std.isOfType(v,Bool))return v?"true":"false";
            if(Std.isOfType(v,String))return quote(v);
            if(isNumber(v)){var n:Float=v;return Math.isFinite(n)?Seed.numberText(n):"null";}
            if(!isObject(v) || isCallable(v))return undef();
            for(o in stack)if(o==v)error("TypeError","Converting circular structure to JSON");
            stack.push(v);
            var inner=indent+gap;var parts:Array<String>=[];var out:String;
            if(Std.isOfType(v,JsArray)) {
                var n=Builtins.lengthOf(v);var j:Float=0;
                while(j<n){var item=serialize(v,Seed.numberText(j),inner);parts.push(item==undef()?"null":item);j++;}
                out=parts.length==0?"[]":gap==""?"["+parts.join(",")+"]":"[\n"+inner+parts.join(",\n"+inner)+"\n"+indent+"]";
            }
            else {
                for(name in (allowed!=null?allowed:keys(v))) {
                    var item=serialize(v,name,inner);
                    if(item!=undef())parts.push(quote(name)+(gap==""?":":": ")+item);
                }
                out=parts.length==0?"{}":gap==""?"{"+parts.join(",")+"}":"{\n"+inner+parts.join(",\n"+inner)+"\n"+indent+"}";
            }
            stack.pop();
            return out;
        }
        return serialize(object([""],[value]),"","");
    }
}
