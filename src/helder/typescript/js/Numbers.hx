package helder.typescript.js;
import helder.typescript.js.Values;
import helder.typescript.js.Symbols.JsSymbol;
import helder.typescript.js.Lib.*;

// Number.prototype methods, number parsing and Math.
class Numbers {
    public static function setup():Void {
        var p=Builtins.NumberProto;
        function method(name:String,arity:Int,fn:(Float,Dynamic)->Dynamic)
            p.setOwn(name,Builtins.nativeFunction(name,arity,(t,a,_)->fn(Builtins.primitive(t,"number"),arg(a,0))),Attr.HIDDEN);
        method("toString",1,(x,radix)->{
            var r=radix==undef()?10:toIntegerOrInfinity(radix);
            if(r<2 || r>36)return error("RangeError","toString() radix must be between 2 and 36");
            return r==10?Seed.numberText(x):radixText(x,Std.int(r));
        });
        method("toLocaleString",0,(x,_)->Seed.numberText(x));
        method("toFixed",1,(x,digits)->{
            var f=toIntegerOrInfinity(digits);
            if(f<0 || f>100)return error("RangeError","toFixed() digits argument must be between 0 and 100");
            if(Math.isNaN(x))return "NaN";
            if(Math.abs(x)>=1e21 || !Math.isFinite(x))return Seed.numberText(x);
            return (x<0?"-":"")+fixed(Math.abs(x),Std.int(f));
        });
        method("toExponential",1,(x,digits)->{
            var f=toIntegerOrInfinity(digits);
            if(!Math.isFinite(x))return Seed.numberText(x);
            if(f<0 || f>100)return error("RangeError","toExponential() argument must be between 0 and 100");
            var sign=x<0?"-":"";x=Math.abs(x);
            var d=digits==undef()?shortest(x):rounded(x,Std.int(f)+1);
            var m=d.digits.length>1?d.digits.charAt(0)+"."+d.digits.substr(1):d.digits;
            return sign+m+"e"+(d.exponent>=0?"+":"-")+Std.string(Std.int(Math.abs(d.exponent)));
        });
        method("toPrecision",1,(x,precision)->{
            if(precision==undef())return Seed.numberText(x);
            var p=toIntegerOrInfinity(precision);
            if(!Math.isFinite(x))return Seed.numberText(x);
            if(p<1 || p>100)return error("RangeError","toPrecision() argument must be between 1 and 100");
            var sign=x<0?"-":"";x=Math.abs(x);
            var d=rounded(x,Std.int(p));var e=d.exponent;
            if(e< -6 || e>=p) {
                var m=d.digits.length>1?d.digits.charAt(0)+"."+d.digits.substr(1):d.digits;
                return sign+m+"e"+(e>=0?"+":"-")+Std.string(Std.int(Math.abs(e)));
            }
            if(e>=0)return sign+(e+1>=d.digits.length?d.digits:d.digits.substr(0,e+1)+"."+d.digits.substr(e+1));
            return sign+"0."+StringTools.lpad("","0",-e-1)+d.digits;
        });
    }

    // Exact decimal expansion of a finite x >= 0: value = digits × 10^power.
    static function exact(x:Float):{digits:String,power:Int} {
        if(x==0)return {digits:"0",power:0};
        var e=Math.floor(Math.log(x)/Math.log(2));
        while(Math.pow(2,e)>x)e--;while(Math.pow(2,e+1)<=x)e++;
        var shift=Std.int(Math.max(e-52,-1074));
        // (scaling by a power of two is exact; done in two steps to avoid overflow)
        var m=x;var s=-shift;while(s>0){var k=Std.int(Math.min(s,1000));m*=Math.pow(2,k);s-=k;}while(s<0){var k=Std.int(Math.min(-s,1000));m/=Math.pow(2,k);s+=k;}
        var limbs:Array<Float>=[];while(m>0){var r=m%10000000;limbs.push(r);m=(m-r)/10000000;}
        function multiply(by:Float) {
            var carry=0.0;
            for(i in 0...limbs.length){var v=limbs[i]*by+carry;var r=v%10000000;limbs[i]=r;carry=(v-r)/10000000;}
            while(carry>0){var r=carry%10000000;limbs.push(r);carry=(carry-r)/10000000;}
        }
        var power=0;
        if(shift>=0){var k=shift;while(k>0){var step=Std.int(Math.min(k,20));multiply(Math.pow(2,step));k-=step;}}
        else {var k=-shift;power=shift;while(k>0){var step=Std.int(Math.min(k,9));multiply(Math.pow(5,step));k-=step;}}
        var b=new StringBuf();var i=limbs.length-1;b.add(Std.string(Std.int(limbs[i])));
        while(i>0){i--;var part=Std.string(Std.int(limbs[i]));b.add(StringTools.lpad(part,"0",7));}
        return {digits:b.toString(),power:power};
    }
    // (decimal digit string plus one)
    static function increment(d:String):String {
        var chars=d.split("");var i=chars.length-1;
        while(i>=0){if(chars[i]=="9"){chars[i]="0";i--;}else{chars[i]=String.fromCharCode(chars[i].charCodeAt(0)+1);return chars.join("");}}
        return "1"+chars.join("");
    }
    // x >= 0 with f fraction digits, ties rounded up (Number.prototype.toFixed).
    static function fixed(x:Float,f:Int):String {
        var d=exact(x);var shift=d.power+f;var n:String;
        if(shift>=0)n=d.digits+StringTools.lpad("","0",shift);
        else {
            var cut=-shift;
            if(cut>d.digits.length)n="0";
            else {
                n=d.digits.substr(0,d.digits.length-cut);if(n=="")n="0";
                if(d.digits.charCodeAt(d.digits.length-cut)>="5".code)n=increment(n);
            }
        }
        while(n.length>1 && n.charAt(0)=="0")n=n.substr(1);
        if(f==0)return n;
        n=StringTools.lpad(n,"0",f+1);
        return n.substr(0,n.length-f)+"."+n.substr(n.length-f);
    }
    // p significant digits of x > 0 (ties up), as digits and the decimal exponent of the first.
    static function rounded(x:Float,p:Int):{digits:String,exponent:Int} {
        if(x==0)return {digits:StringTools.lpad("","0",p),exponent:0};
        var d=exact(x);var digits=d.digits;var exponent=digits.length-1+d.power;
        if(digits.length>p){var up=digits.charCodeAt(p)>="5".code;digits=digits.substr(0,p);if(up){var next=increment(digits);if(next.length>p){next=next.substr(0,p);exponent++;}digits=next;}}
        else digits=StringTools.rpad(digits,"0",p);
        return {digits:digits,exponent:exponent};
    }
    // The shortest round-tripping digits of x > 0 (from the number's text form).
    static function shortest(x:Float):{digits:String,exponent:Int} {
        if(x==0)return {digits:"0",exponent:0};
        var text=Seed.numberText(x);var exponent=0;var e=text.indexOf("e");
        if(e>=0){exponent=Std.parseInt(text.substr(e+1));text=text.substr(0,e);}
        var dot=text.indexOf(".");var intPart=dot<0?text:text.substr(0,dot);var frac=dot<0?"":text.substr(dot+1);
        var all=intPart+frac;var lead=0;while(lead<all.length-1 && all.charAt(lead)=="0")lead++;
        exponent+=intPart.length-1-lead;var digits=all.substr(lead);
        while(digits.length>1 && digits.charAt(digits.length-1)=="0")digits=digits.substr(0,digits.length-1);
        return {digits:digits,exponent:exponent};
    }
    static function nextDouble(v:Float):Float {
        if(v==0)return 5e-324;
        var e=Math.floor(Math.log(v)/Math.log(2));while(Math.pow(2,e)>v)e--;while(Math.pow(2,e+1)<=v)e++;
        return v+Math.pow(2,Math.max(e-52,-1074));
    }
    // V8's DoubleToRadixCString: fraction digits only up to the double's precision.
    static function radixText(value:Float,radix:Int):String {
        if(Math.isNaN(value))return "NaN";
        if(!Math.isFinite(value))return value<0?"-Infinity":"Infinity";
        var chars="0123456789abcdefghijklmnopqrstuvwxyz";
        var negative=value<0;if(negative)value=-value;
        var integer=Math.ffloor(value);var fraction=value-integer;
        var delta=Math.max(nextDouble(0),0.5*(nextDouble(value)-value));
        var frac:Array<Int>=[];
        if(fraction>=delta) {
            do {
                fraction*=radix;delta*=radix;
                var digit=Std.int(fraction);frac.push(digit);fraction-=digit;
                if(fraction>0.5 || fraction==0.5 && digit & 1==1) {
                    if(fraction+delta>1) {
                        // (round up, carrying through written digits)
                        while(true) {
                            if(frac.length==0){integer+=1;break;}
                            var last=frac.pop();
                            if(last+1<radix){frac.push(last+1);break;}
                        }
                        break;
                    }
                }
            } while(fraction>=delta);
        }
        var intDigits=new StringBuf();var parts:Array<String>=[];
        while(integer/radix>=9007199254740992.0){integer/=radix;parts.push("0");}
        do {var r=integer%radix;parts.push(chars.charAt(Std.int(r)));integer=(integer-r)/radix;} while(integer>0);
        parts.reverse();
        var out=(negative?"-":"")+parts.join("");
        if(frac.length>0)out+="."+[for(d in frac)chars.charAt(d)].join("");
        return out;
    }

    public static function parseInteger(s:String,radixValue:Dynamic):Float {
        var start=0;while(start<s.length && Seed.whitespace(s.charCodeAt(start)))start++;var sign:Float=1;
        if(s.charAt(start)=="-"||s.charAt(start)=="+"){if(s.charAt(start)=="-")sign=-1;start++;}
        var radix=radixValue==undef()?0:toInt32(radixValue);if(radix!=0 && (radix<2 || radix>36))return Math.NaN;
        var strip=radix==0 || radix==16;if(radix==0)radix=10;if(strip && s.substr(start,2).toLowerCase()=="0x"){radix=16;start+=2;}
        var result:Float=0;var count=0;var digits=new StringBuf();
        while(start<s.length){var c=s.charCodeAt(start++);var d=c>=48&&c<=57?c-48:c>=65&&c<=90?c-55:c>=97&&c<=122?c-87:-1;if(d<0 || d>=radix)break;result=result*radix+d;digits.addChar(c);count++;}
        if(count==0)return Math.NaN;
        // (decimal digits beyond double precision are parsed exactly)
        if(radix==10 && result>=9007199254740992.0)result=Std.parseFloat(digits.toString());
        return sign*result;
    }
    public static function parseDecimalPrefix(s:String):Float {
        var start=0;while(start<s.length && Seed.whitespace(s.charCodeAt(start)))start++;
        var i=start;if(s.charAt(i)=="+"||s.charAt(i)=="-")i++;if(s.substr(i,8)=="Infinity")return s.charAt(start)=="-"?Math.NEGATIVE_INFINITY:Math.POSITIVE_INFINITY;
        var digits=0;while(i<s.length && s.charCodeAt(i)>=48 && s.charCodeAt(i)<=57){i++;digits++;}if(s.charAt(i)=="."){i++;while(i<s.length&&s.charCodeAt(i)>=48&&s.charCodeAt(i)<=57){i++;digits++;}}
        if(digits==0)return Math.NaN;var end=i;if(s.charAt(i)=="e"||s.charAt(i)=="E"){i++;if(s.charAt(i)=="+"||s.charAt(i)=="-")i++;var exponent=i;while(i<s.length&&s.charCodeAt(i)>=48&&s.charCodeAt(i)<=57)i++;if(i>exponent)end=i;}
        var text=s.substring(start,end);if(StringTools.endsWith(text,"."))text=text.substr(0,text.length-1);
        if(StringTools.startsWith(text,".") || StringTools.startsWith(text,"-.") || StringTools.startsWith(text,"+."))text=StringTools.replace(text,".","0.");
        return Std.parseFloat(text);
    }
    public static function half(value:Float):Float {
        if(!Math.isFinite(value) || value==0)return value;
        var a=Math.abs(value);if(a>=65520)return value<0?Math.NEGATIVE_INFINITY:Math.POSITIVE_INFINITY;
        var unit=0.000000059604644775390625; // 2^-24, the subnormal spacing
        if(a>=0.00006103515625) {
            var e=Math.ffloor(Math.log(a)/Math.log(2)),power=Math.pow(2,e);
            while(power>a){e--;power/=2;}while(power*2<=a){e++;power*=2;}
            unit=Math.pow(2,e-10);
        }
        var scaled=a/unit,n=Math.ffloor(scaled),fraction=scaled-n;
        if(fraction>0.5 || fraction==0.5 && n%2!=0)n++;
        var rounded=n*unit;return value<0?-rounded:rounded;
    }
    public static function math(name:String,a:Float,b:Float):Float {
        return switch(name){
            case "abs":Math.abs(a);case "floor":Math.ffloor(a);case "ceil":Math.fceil(a);case "trunc":a<0?Math.fceil(a):Math.ffloor(a);
            case "round":if(a<0 && a>=-0.5)-0.0;else if(!Math.isFinite(a) || Math.abs(a)>=4503599627370496.0)a;else Math.ffloor(a+0.5);
            case "sqrt":Math.sqrt(a);case "cbrt":if(a==0 || !Math.isFinite(a))a;else{var r=a<0?-Math.pow(-a,1/3):Math.pow(a,1/3);var rr=Math.fround(r);if(rr*rr*rr==a)rr;else r;};
            case "pow":Seed.power(a,b);
            case "sin":Math.sin(a);case "cos":Math.cos(a);case "tan":Math.tan(a);case "asin":Math.asin(a);case "acos":Math.acos(a);case "atan":Math.atan(a);case "atan2":Math.atan2(a,b);
            case "exp":Math.exp(a);case "expm1":Math.abs(a)<1e-5?a+a*a/2+a*a*a/6:Math.exp(a)-1;
            case "log":Math.log(a);case "log1p":Math.abs(a)<1e-4?a-a*a/2+a*a*a/3:Math.log(1+a);
            case "log2":var r=Math.log(a)/Math.log(2);var n=Math.fround(r);if(Math.pow(2,n)==a)n;else r;
            case "log10":var r=Math.log(a)/Math.log(10);var n=Math.fround(r);if(Math.pow(10,n)==a)n;else r;
            case "sign":Math.isNaN(a)||a==0?a:a<0?-1:1;
            case "sinh":(Math.exp(a)-Math.exp(-a))/2;case "cosh":(Math.exp(a)+Math.exp(-a))/2;case "tanh":if(a>20)1;else if(a< -20)-1;else{var e=Math.exp(2*a);(e-1)/(e+1);};
            case "asinh":a==0?a:a<0?-Math.log(-a+Math.sqrt(a*a+1)):Math.log(a+Math.sqrt(a*a+1));case "acosh":Math.log(a+Math.sqrt(a*a-1));case "atanh":a==0?a:0.5*Math.log((1+a)/(1-a));
            case "clz32":var v=toInt32(a);var n=0;while(n<32 && (v & 0x80000000)==0){v<<=1;n++;}n;
            case "f16round":half(a);
            case "fround":haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(a));
            case _:Math.NaN;
        };
    }
}
