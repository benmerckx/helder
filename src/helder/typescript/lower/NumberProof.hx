package helder.typescript.lower;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
using Lambda;

// Whole-file proof that a binding or top-level function result always holds a
// JavaScript number. It does not trust declared types (`any`, assertions, `var`
// and missing arguments can all put other values behind `number`); it follows
// every value that can flow in. Proven bindings lower to F64, everything else
// stays dynamic. Closure parameters, fields and functions used as values are
// never proven.
class NumberProof {
    var src:Project;
    var values:Map<String,Array<Node>>=[];
    var results:Map<String,Array<Node>>=[];
    var functions:Map<String,Node>=[];
    var provenValues:Map<String,Bool>=[];
    var provenResults:Map<String,Bool>=[];
    public function new(src:Project,file:SourceFile) {
        this.src=src;
        var statements=file.root.statements();if(statements==null)statements=[];
        // (only functions the frontend calls directly: see Frontend.direct)
        for(n in statements)if(n.kind==KindFunctionDeclaration && n.name()!=null && n.body()!=null && Frontend.isDirect(n))functions.set(n.name().text,n);
        for(name=>f in functions)declareFunction(name,f);
        // (exported functions are called from other modules)
        for(name=>f in functions)if(Frontend.isExported(f))escape(name);
        collect(file.root);
        for(s=>sources in values)if(sources.indexOf(null)<0)provenValues.set(s,true);
        for(name=>sources in results)if(sources.indexOf(null)<0)provenResults.set(name,true);
        var changed=true;
        while(changed) {
            changed=false;
            for(s in provenValues.keys())if(!values.get(s).foreach(isNumber)){provenValues.remove(s);changed=true;}
            for(name in provenResults.keys())if(!results.get(name).foreach(isNumber)){provenResults.remove(name);changed=true;}
        }
    }
    public function binding(declaration:Node):Bool {
        var s=symbol(declaration.name());return s!=null && provenValues.exists(s);
    }
    public function result(name:String):Bool return provenResults.exists(name);
    function parameters(f:Node):Array<Node> return Frontend.parametersOf(f);
    function symbol(n:Node):Null<String> return n==null || n.kind!=KindIdentifier?null:n.symbol;
    function flow(s:Null<String>,source:Null<Node>) {var list=s==null?null:values.get(s);if(list!=null)list.push(source);}
    function declareFunction(name:String,f:Node) {
        var arguments=Frontend.usesArguments(f.body());
        for(a in parameters(f))
            values.set(symbol(a.name()),!arguments && a.name().kind==KindIdentifier && a.initializer()==null && a.questionToken()==null && a.dotDotDotToken()==null?[]:[null]);
        var returns:Array<Node>=[];
        var body=f.body().statements();
        if(body==null || body.length==0 || body[body.length-1].kind!=KindReturnStatement)returns.push(null);
        function visit(n:Node) {
            if(n==null || n.kind==KindFunctionDeclaration || n.kind==KindFunctionExpression || n.kind==KindArrowFunction || n.kind==KindClassDeclaration || n.kind==KindClassExpression)return;
            if(n.kind==KindReturnStatement)returns.push(n.expression());
            for(c in n.children())visit(c);
        }
        visit(f.body());results.set(name,returns);
    }
    function escape(name:String) {
        for(a in parameters(functions.get(name)))flow(symbol(a.name()),null);
        results.get(name).push(null);
    }
    function collect(n:Node) {
        if(n==null)return;
        switch(n.kind) {
            case KindVariableDeclaration if(n.name().kind==KindIdentifier):
                var list=n.parent;var s=symbol(n.name());
                if(n.initializer()!=null) {
                    if(list.flags & NodeFlags.BlockScoped!=0 && !values.exists(s))values.set(s,[]);
                    flow(s,n.initializer());
                }
                else if(list.parent!=null && (list.parent.kind==KindForOfStatement || list.parent.kind==KindForInStatement))flow(s,null);
            case KindIdentifier if(functions.exists(n.text)):
                var parent=n.parent;
                if(parent.kind==KindCallExpression && parent.expression()==n) {
                    var args=parent.arguments();if(args==null)args=[];
                    var params=parameters(functions.get(n.text));
                    for(i in 0...params.length)flow(symbol(params[i].name()),i<args.length && !args.exists(a->a.kind==KindSpreadElement)?args[i]:null);
                }
                else if(parent!=functions.get(n.text))escape(n.text);
            case KindBinaryExpression:
                var x=n;var op=x.operatorToken().kind;
                if(op>=KindFirstAssignment && op<=KindLastAssignment && x.left().kind==KindIdentifier) {
                    var s=symbol(x.left());
                    if(op==KindEqualsToken || op==KindPlusEqualsToken)flow(s,x.right());
                    else if(op==KindBarBarEqualsToken || op==KindAmpersandAmpersandEqualsToken || op==KindQuestionQuestionEqualsToken)flow(s,null);
                }
            case _:
        }
        for(c in n.children())collect(c);
    }
    // True when the lowering of n always yields a number, given the current proofs.
    function isNumber(n:Null<Node>):Bool {
        if(n==null)return false;
        return switch(n.kind) {
            case KindNumericLiteral:true;
            case KindIdentifier:n.text=="NaN" || n.text=="Infinity" || {var s=symbol(n);s!=null && provenValues.exists(s);};
            case KindParenthesizedExpression:isNumber(n.expression());
            case KindPrefixUnaryExpression:n.unaryOperator()!=KindExclamationToken;
            case KindPostfixUnaryExpression:true;
            case KindConditionalExpression:var c=n;isNumber(c.whenTrue()) && isNumber(c.whenFalse());
            case KindCallExpression:var callee=n.expression();callee.kind==KindIdentifier && provenResults.exists(callee.text) && symbol(callee)==symbol(functions.get(callee.text).name());
            case KindBinaryExpression:
                var x=n;
                switch(x.operatorToken().kind) {
                    case KindMinusToken|KindAsteriskToken|KindSlashToken|KindPercentToken|KindAmpersandToken|KindBarToken|KindCaretToken
                        |KindLessThanLessThanToken|KindGreaterThanGreaterThanToken|KindGreaterThanGreaterThanGreaterThanToken
                        |KindAsteriskAsteriskToken|KindMinusEqualsToken|KindAsteriskEqualsToken|KindSlashEqualsToken|KindPercentEqualsToken
                        |KindAsteriskAsteriskEqualsToken|KindLessThanLessThanEqualsToken|KindGreaterThanGreaterThanEqualsToken
                        |KindGreaterThanGreaterThanGreaterThanEqualsToken|KindAmpersandEqualsToken|KindBarEqualsToken|KindCaretEqualsToken:true;
                    case KindPlusToken:isNumber(x.left()) && isNumber(x.right());
                    case KindPlusEqualsToken:x.left().kind==KindIdentifier && isNumber(x.left()) && isNumber(x.right());
                    case KindEqualsToken:isNumber(x.right());
                    case _:false;
                }
            case _:false;
        };
    }
}
