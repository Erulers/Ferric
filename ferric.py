#!/usr/bin/env python3
"""FERRIC reference toolchain 0.3: lexer, parser, evaluator and runtime.

FERRIC is a call-oriented experimental language. This implementation is an
interpreter/reference runtime, not the native NASM compiler. It deliberately
keeps all language semantics in this file so the toolchain has no dependencies
outside the Python standard library.
"""
from __future__ import annotations
import argparse, json, math, operator, re, sys, time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

VERSION = "0.3.0-reference"

@dataclass
class Token:
    kind: str
    value: str
    line: int
    column: int

class FerricError(Exception):
    def __init__(self, message: str, token: Token | None = None):
        self.message, self.token = message, token
        where = f"{token.line}:{token.column}: " if token else ""
        super().__init__(where + message)

@dataclass
class Node:
    kind: str
    value: Any = None
    children: list["Node"] | None = None
    line: int = 1
    column: int = 1
    def json(self):
        return {"kind": self.kind, "value": self.value,
                "children": [c.json() for c in (self.children or [])],
                "line": self.line, "column": self.column}

TOKEN_RE = re.compile(r'''(?P<WS>[ \t\r]+)|(?P<NL>\n)|(?P<COMMENT>//[^\n]*|\#[^\n]*)|(?P<BLOCK>/\*[\s\S]*?\*/)|(?P<STRING>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?P<FLOAT>(?:\d+\.\d*|\.\d+)(?:[eE][+-]?\d+)?|\d+[eE][+-]?\d+)|(?P<INT>\d+)|(?P<ID>[A-Za-z_][A-Za-z_0-9]*)|(?P<OP>==|!=|<=|>=|&&|\|\||<<|>>|\+=|-=|\*=|/=|->|::|[{}()\[\],;:.?+*/%=<>!&|^~-])''')

def lex(source: str) -> list[Token]:
    out=[]; i=0; line=1; col=1
    while i < len(source):
        m=TOKEN_RE.match(source, i)
        if not m:
            raise FerricError(f"unexpected character {source[i]!r}", Token("ERROR", source[i], line, col))
        kind=m.lastgroup or "ERROR"; value=m.group(); startline,startcol=line,col; i=m.end()
        if kind == "NL": line += 1; col=1; continue
        if kind in ("WS", "COMMENT", "BLOCK"):
            n=value.count("\n")
            if n: line += n; col=len(value.rsplit("\n",1)[-1])+1
            else: col += len(value)
            continue
        out.append(Token(kind,value,startline,startcol)); col += len(value)
    out.append(Token("EOF","",line,col))
    return out

PRECEDENCE={"||":1,"&&":2,"|":3,"^":4,"&":5,"==":6,"!=":6,"<":7,"<=":7,">":7,">=":7,"<<":8,">>":8,"+":9,"-":9,"*":10,"/":10,"%":10}
class Parser:
    def __init__(self,tokens): self.t=tokens; self.i=0
    @property
    def cur(self): return self.t[min(self.i,len(self.t)-1)]
    def take(self): x=self.cur; self.i+=1; return x
    def accept(self,v):
        if self.cur.value==v: return self.take()
        return None
    def expect(self,v):
        x=self.accept(v)
        if not x: raise FerricError(f"expected {v!r}, found {self.cur.value or 'end of file'!r}",self.cur)
        return x
    def program(self):
        items=[]
        while self.cur.kind!="EOF":
            if self.accept(";"): continue
            items.append(self.statement())
        return Node("program",children=items)
    def statement(self):
        expr=self.expression()
        if self.accept("{"):
            body=[]
            while self.cur.kind!="EOF" and self.cur.value!="}":
                if self.accept(";"): continue
                body.append(self.statement())
            self.expect("}")
            return Node("block",children=[expr,*body],line=expr.line,column=expr.column)
        self.accept(";")
        return expr
    def expression(self,minp=0):
        tok=self.take()
        if tok.kind=="INT": left=Node("int",int(tok.value),line=tok.line,column=tok.column)
        elif tok.kind=="FLOAT": left=Node("float",float(tok.value),line=tok.line,column=tok.column)
        elif tok.kind=="STRING":
            try:
                if tok.value[0]=='"': val=json.loads(tok.value)
                else: val=bytes(tok.value[1:-1],"utf8").decode("unicode_escape")
            except Exception as e: raise FerricError(f"invalid string literal: {e}",tok)
            left=Node("string",val,line=tok.line,column=tok.column)
        elif tok.kind=="ID":
            if tok.value in ("true","false"): left=Node("bool",tok.value=="true",line=tok.line,column=tok.column)
            elif tok.value=="null": left=Node("null",None,line=tok.line,column=tok.column)
            else: left=Node("name",tok.value,line=tok.line,column=tok.column)
        elif tok.value in ("-","!","~"):
            left=Node("unary",tok.value,[self.expression(11)],tok.line,tok.column)
        elif tok.value=="(":
            left=self.expression(); self.expect(")")
        else: raise FerricError(f"expected an expression, found {tok.value or 'end of file'!r}",tok)
        while True:
            if self.cur.value=="(":
                op=self.take(); args=[]
                if self.cur.value!=")":
                    while True:
                        args.append(self.expression())
                        if not self.accept(","): break
                self.expect(")"); left=Node("call",children=[left,*args],line=op.line,column=op.column); continue
            if self.cur.value==".":
                self.take(); name=self.take()
                if name.kind!="ID": raise FerricError("expected member name after '.'",name)
                left=Node("member",name.value,[left],name.line,name.column); continue
            op=self.cur.value; p=PRECEDENCE.get(op,-1)
            if p<minp: break
            self.take(); right=self.expression(p+1)
            left=Node("binary",op,[left,right],tok.line,tok.column)
        return left

@dataclass
class Value:
    type: str
    data: Any

@dataclass
class Binding:
    value: Value
    mutable: bool = False

@dataclass
class Thunk:
    node: Node

class ReturnSignal(Exception):
    def __init__(self,value): self.value=value
class BreakSignal(Exception): pass
class ContinueSignal(Exception): pass

@dataclass
class FunctionDef:
    name: str
    parameters: list[str]
    body: list[Node]
    line: int

SYMBOLS={"text","string","integer","int","float","boolean","bool","void","private","public","io","read_only","read_write","process","global","discard","byte","array","map","any","never","condition","mut","const","static","heap","stack","pure","unsafe","async","await","yield"}
ALIASES={"text":"text","string":"text","int":"integer","integer":"integer","bool":"boolean","boolean":"boolean","float":"float","byte":"byte","array":"array","map":"map","any":"any","void":"void","null":"null"}

def name_of(n:Node)->str:
    if n.kind=="name": return n.value
    if n.kind=="member": return name_of(n.children[0])+"."+n.value
    raise FerricError("expected a function or member name",Token("ERROR","",n.line,n.column))

def infer_type(x):
    if isinstance(x,bool): return "boolean"
    if isinstance(x,int): return "integer"
    if isinstance(x,float): return "float"
    if isinstance(x,str): return "text"
    if isinstance(x,list): return "array"
    if isinstance(x,dict): return "map"
    if x is None: return "null"
    return "any"

class Runtime:
    def __init__(self, max_steps=1_000_000):
        self.scopes=[{}]; self.output=[]; self.declarations=0; self.functions={}
        self.steps=0; self.max_steps=max_steps; self.loop_depth=0; self.started=time.perf_counter()
    def tick(self,node=None):
        self.steps+=1
        if self.steps>self.max_steps: raise FerricError(f"execution step limit ({self.max_steps}) exceeded; possible infinite loop",Token("ERROR","",getattr(node,"line",1),getattr(node,"column",1)))
    def lookup_binding(self,n):
        for s in reversed(self.scopes):
            if n in s: return s[n]
        raise FerricError(f"undeclared identifier {n!r}")
    def lookup(self,n): return self.lookup_binding(n).value
    def push(self): self.scopes.append({})
    def pop(self): self.scopes.pop()
    def truth(self,v): return bool(v.data)
    def eval(self,n:Node):
        self.tick(n)
        if n.kind in ("int","float","string","bool","null"):
            return Value({"int":"integer","float":"float","string":"text","bool":"boolean","null":"null"}[n.kind],n.value)
        if n.kind=="name":
            if n.value in SYMBOLS: return Value("symbol",n.value)
            return self.lookup(n.value)
        if n.kind=="member": return Value("symbol",name_of(n))
        if n.kind=="unary":
            v=self.eval(n.children[0]).data
            try: result={"-":operator.neg,"!":lambda x:not x,"~":operator.invert}[n.value](v)
            except (TypeError,ValueError) as e: raise FerricError(f"invalid unary {n.value}: {e}",Token("ERROR",n.value,n.line,n.column))
            return Value(infer_type(result),result)
        if n.kind=="binary":
            # Boolean operators short-circuit, unlike eager function arguments.
            if n.value=="&&":
                a=self.eval(n.children[0]); return Value("boolean",self.truth(a) and self.truth(self.eval(n.children[1])))
            if n.value=="||":
                a=self.eval(n.children[0]); return Value("boolean",self.truth(a) or self.truth(self.eval(n.children[1])))
            a=self.eval(n.children[0]).data; b=self.eval(n.children[1]).data
            ops={"+":operator.add,"-":operator.sub,"*":operator.mul,"/":operator.truediv,"%":operator.mod,"==":operator.eq,"!=":operator.ne,"<":operator.lt,"<=":operator.le,">":operator.gt,">=":operator.ge,"&":operator.and_,"|":operator.or_,"^":operator.xor,"<<":operator.lshift,">>":operator.rshift}
            if n.value in ("/","%") and b==0: raise FerricError("division by zero",Token("ERROR",n.value,n.line,n.column))
            try: result=ops[n.value](a,b)
            except (TypeError,ValueError,OverflowError,ZeroDivisionError) as e: raise FerricError(f"invalid operands for {n.value}: {e}",Token("ERROR",n.value,n.line,n.column))
            return Value(infer_type(result),result)
        if n.kind=="block": return self.eval_block(n)
        if n.kind=="program":
            result=Value("void",None)
            for c in n.children: result=self.eval(c)
            return result
        if n.kind=="call": return self.call(name_of(n.children[0]),n.children[1:],n)
        raise FerricError(f"unsupported syntax node {n.kind}")
    def eval_block_body(self, statements, new_scope=True):
        if new_scope: self.push()
        try:
            result=Value("void",None)
            for stmt in statements: result=self.eval(stmt)
            return result
        finally:
            if new_scope: self.pop()
    def eval_block(self,n):
        head=n.children[0]; body=n.children[1:]
        if head.kind=="call":
            fn=name_of(head.children[0]); args=head.children[1:]
            if fn in ("module","scope"):
                return self.eval_block_body(body,True)
            if fn=="define_function":
                if len(args)<2: raise FerricError("define_function(name, parameters(...)) requires two arguments")
                name=self.eval(args[0]).data
                if not isinstance(name,str): raise FerricError("function name must be text")
                pnode=args[1]
                if pnode.kind!="call" or name_of(pnode.children[0])!="parameters": raise FerricError("second argument must be parameters(...)")
                params=[self.eval(a).data for a in pnode.children[1:]]
                if not all(isinstance(p,str) for p in params): raise FerricError("parameter names must be text")
                if len(set(params))!=len(params): raise FerricError("duplicate function parameter")
                self.functions[name]=FunctionDef(name,params,body,n.line)
                return Value("void",None)
            if fn in ("while_loop","if_true","if_false"):
                if len(args)!=1: raise FerricError(f"{fn} expects condition(expression)")
                cond=args[0]
                if cond.kind!="call" or name_of(cond.children[0])!="condition" or len(cond.children)!=2:
                    raise FerricError(f"{fn} expects condition(expression); the expression is re-evaluated each time")
                thunk=Thunk(cond.children[1])
                if fn=="if_true":
                    return self.eval_block_body(body,True) if self.truth(self.eval(thunk.node)) else Value("void",None)
                if fn=="if_false":
                    return self.eval_block_body(body,True) if not self.truth(self.eval(thunk.node)) else Value("void",None)
                count=0; result=Value("void",None); self.loop_depth+=1
                try:
                    while self.truth(self.eval(thunk.node)):
                        count+=1
                        if count>self.max_steps: raise FerricError("loop iteration limit exceeded")
                        try: result=self.eval_block_body(body,True)
                        except ContinueSignal: continue
                        except BreakSignal: break
                finally: self.loop_depth-=1
                return result
            if fn=="for_range":
                if len(args) not in (3,4): raise FerricError("for_range(name, start, stop [, step]) expects 3 or 4 arguments")
                var=self.eval(args[0]).data; start=self.eval(args[1]).data; stop=self.eval(args[2]).data; step=self.eval(args[3]).data if len(args)==4 else 1
                if not isinstance(var,str) or not all(isinstance(x,int) for x in (start,stop,step)) or step==0: raise FerricError("for_range needs a text name and integer bounds/step (nonzero step)")
                result=Value("void",None); self.loop_depth+=1
                try:
                    for i in range(start,stop,step):
                        self.push(); self.scopes[-1][var]=Binding(Value("integer",i),False)
                        try:
                            for stmt in body: result=self.eval(stmt)
                        except ContinueSignal: pass
                        except BreakSignal: break
                        finally: self.pop()
                finally: self.loop_depth-=1
                return result
        return self.eval_block_body(n.children,True)
    def call(self,fn,args,node):
        self.tick(node)
        if fn=="condition":
            if len(args)!=1: raise FerricError("condition(expression) expects one expression")
            return Value("condition",Thunk(args[0]))
        if fn in {"version","lifetime","mutable","visibility","expected_type","access","effects","result","discard","arguments","function","parameters","returns","throws","annotations","attributes","generic","where","ownership","alignment","calling_convention","memory_order","permission","capability","optimization","target","feature","contract","requires","ensures","invariant","deprecation","since","author","license","documentation","tag","metadata"}:
            return Value("metadata",(fn,[self.eval(a) for a in args]))
        if fn=="value":
            if len(args)!=2: raise FerricError("value(type, expression) expects two arguments")
            typ=self.eval(args[0]).data; val=self.eval(args[1])
            if ALIASES.get(str(typ),str(typ)) not in (ALIASES.get(val.type,val.type),"any") and val.type!="null":
                raise FerricError(f"value type mismatch: expected {typ}, got {val.type}")
            return Value(ALIASES.get(str(typ),str(typ)),val.data)
        if fn=="declare":
            if len(args)<3: raise FerricError("declare(type, name, value(...), [mutable(...)]) expects at least three arguments")
            typ=self.eval(args[0]).data; ident=self.eval(args[1]).data
            if not isinstance(ident,str): raise FerricError("declaration name must be text")
            if ident in self.scopes[-1]: raise FerricError(f"duplicate declaration {ident!r}")
            init=self.eval(args[2]); expected=ALIASES.get(str(typ),str(typ))
            if init.type not in (expected,"metadata","any") and expected!="any": raise FerricError(f"type mismatch: declared {typ}, initialized with {init.type}")
            mut=False
            for extra in args[3:]:
                if extra.kind=="call" and name_of(extra.children[0])=="mutable" and len(extra.children)>1:
                    mut=bool(self.eval(extra.children[1]).data)
            self.scopes[-1][ident]=Binding(init,mut); self.declarations+=1
            return Value("void",None)
        if fn in ("reference","get_variable"):
            if not args: raise FerricError(f"{fn}(name, ...) expects a name")
            ident=self.eval(args[0]).data
            if not isinstance(ident,str): raise FerricError("variable reference name must be text")
            return self.lookup(ident)
        if fn in ("assign","set_variable"):
            if len(args)!=2: raise FerricError("assign(name, expression) expects two arguments")
            ident=self.eval(args[0]).data; val=self.eval(args[1])
            binding=self.lookup_binding(ident)
            if not binding.mutable: raise FerricError(f"cannot assign to immutable variable {ident!r}; declare it with mutable(true)")
            old=binding.value; expected=ALIASES.get(old.type,old.type)
            if expected not in (ALIASES.get(val.type,val.type),"any") and val.type!="null": raise FerricError(f"assignment type mismatch: {old.type} cannot receive {val.type}")
            binding.value=Value(old.type,val.data); return binding.value
        if fn in ("array","array_new"):
            vals=[self.eval(a) for a in args]
            if len(vals)==1 and vals[0].type=="integer":
                size=vals[0].data
                if size<0 or size>10_000_000: raise FerricError("array size must be between 0 and 10,000,000")
                return Value("array",[0 for _ in range(size)])
            if len(vals)==2 and vals[0].type=="integer":
                size,fill=vals[0].data,vals[1].data
                if size<0 or size>10_000_000: raise FerricError("array size must be between 0 and 10,000,000")
                return Value("array",[fill for _ in range(size)])
            return Value("array",[v.data for v in vals])
        if fn in ("array_get","get_index"):
            if len(args)!=2: raise FerricError("array_get(array, index) expects two arguments")
            arr=self.eval(args[0]).data; idx=self.eval(args[1]).data
            if not isinstance(arr,list) or not isinstance(idx,int): raise FerricError("array_get requires an array and integer index")
            try: val=arr[idx]
            except IndexError: raise FerricError(f"array index {idx} out of bounds for length {len(arr)}")
            return Value(infer_type(val),val)
        if fn in ("array_set","set_index"):
            if len(args)!=3: raise FerricError("array_set(array, index, value) expects three arguments")
            arr=self.eval(args[0]).data; idx=self.eval(args[1]).data; val=self.eval(args[2]).data
            if not isinstance(arr,list) or not isinstance(idx,int): raise FerricError("array_set requires an array and integer index")
            if idx<0 or idx>=len(arr): raise FerricError(f"array index {idx} out of bounds for length {len(arr)}")
            arr[idx]=val; return Value(infer_type(val),val)
        if fn=="array_push":
            if len(args)!=2: raise FerricError("array_push(array, value) expects two arguments")
            arr=self.eval(args[0]).data; val=self.eval(args[1]).data
            if not isinstance(arr,list): raise FerricError("array_push first argument must be an array")
            arr.append(val); return Value("integer",len(arr))
        if fn=="array_pop":
            if len(args)!=1: raise FerricError("array_pop(array) expects one argument")
            arr=self.eval(args[0]).data
            if not isinstance(arr,list) or not arr: raise FerricError("array_pop requires a non-empty array")
            val=arr.pop(); return Value(infer_type(val),val)
        if fn in ("length","len"):
            if len(args)!=1: raise FerricError("length(value) expects one argument")
            val=self.eval(args[0]).data
            if not isinstance(val,(str,list,dict,tuple)): raise FerricError("length expects text, array, or map")
            return Value("integer",len(val))
        if fn=="map_new": return Value("map",{})
        if fn=="map_set":
            if len(args)!=3: raise FerricError("map_set(map, key, value) expects three arguments")
            m=self.eval(args[0]).data; k=self.eval(args[1]).data; v=self.eval(args[2]).data
            if not isinstance(m,dict): raise FerricError("map_set first argument must be a map")
            m[k]=v; return Value(infer_type(v),v)
        if fn=="map_get":
            if len(args) not in (2,3): raise FerricError("map_get(map, key [, default]) expects two or three arguments")
            m=self.eval(args[0]).data; k=self.eval(args[1]).data; default=self.eval(args[2]).data if len(args)==3 else None
            if not isinstance(m,dict): raise FerricError("map_get first argument must be a map")
            v=m.get(k,default); return Value(infer_type(v),v)
        if fn=="invoke":
            if not args: raise FerricError("invoke expects function(name)")
            f=args[0]
            if f.kind!="call" or name_of(f.children[0])!="function" or len(f.children)<2: raise FerricError("invoke first argument must be function(name)")
            target=self.eval(f.children[1]).data
            if target in ("stdout.write","stdout.write_line","io.print","io.println"):
                if len(args)<2 or args[1].kind!="call" or name_of(args[1].children[0])!="arguments": raise FerricError(f"{target} expects arguments(...)")
                vals=[self.eval(a).data for a in args[1].children[1:]]
                self.output.append("".join(map(str,vals))+ ("\n" if target in ("stdout.write_line","io.println") else ""))
                return Value("void",None)
            raise FerricError(f"unknown function {target!r}")
        if fn in ("print","write","stdout_write"):
            self.output.append("".join(str(self.eval(a).data) for a in args)); return Value("void",None)
        if fn in ("println","print_line","write_line"):
            self.output.append(" ".join(str(self.eval(a).data) for a in args)+"\n"); return Value("void",None)
        if fn=="assert":
            if len(args)!=1 or not self.eval(args[0]).data: raise FerricError("assertion failed")
            return Value("void",None)
        if fn=="assert_equal":
            if len(args)!=2: raise FerricError("assert_equal(actual, expected) expects two arguments")
            a=self.eval(args[0]).data; b=self.eval(args[1]).data
            if a!=b: raise FerricError(f"assertion failed: {a!r} != {b!r}")
            return Value("void",None)
        if fn=="sqrt": return Value("float",math.sqrt(self.eval(args[0]).data))
        if fn=="abs": return Value(infer_type(abs(self.eval(args[0]).data)),abs(self.eval(args[0]).data))
        if fn in ("min","max"):
            vals=[self.eval(a).data for a in args]
            if not vals: raise FerricError(f"{fn} expects at least one argument")
            result=(min if fn=="min" else max)(vals); return Value(infer_type(result),result)
        if fn=="pow":
            if len(args)!=2: raise FerricError("pow(base, exponent) expects two arguments")
            v=pow(self.eval(args[0]).data,self.eval(args[1]).data); return Value(infer_type(v),v)
        if fn in ("floor","ceil","round"):
            if len(args)!=1: raise FerricError(f"{fn} expects one argument")
            x=self.eval(args[0]).data; f={"floor":math.floor,"ceil":math.ceil,"round":round}[fn]; v=f(x); return Value(infer_type(v),v)
        if fn=="hex":
            if len(args)!=1: raise FerricError("hex(integer) expects one argument")
            return Value("text",hex(int(self.eval(args[0]).data)))
        if fn=="binary":
            if len(args)!=1: raise FerricError("binary(integer) expects one argument")
            return Value("text",bin(int(self.eval(args[0]).data)))
        if fn=="type_of":
            if len(args)!=1: raise FerricError("type_of(value) expects one argument")
            return Value("text",self.eval(args[0]).type)
        if fn=="to_integer": return Value("integer",int(self.eval(args[0]).data))
        if fn=="to_float": return Value("float",float(self.eval(args[0]).data))
        if fn=="to_text": return Value("text",str(self.eval(args[0]).data))
        if fn=="clock_ms": return Value("integer",int((time.perf_counter()-self.started)*1000))
        if fn=="break_loop":
            if not self.loop_depth: raise FerricError("break_loop used outside a loop")
            raise BreakSignal()
        if fn=="continue_loop":
            if not self.loop_depth: raise FerricError("continue_loop used outside a loop")
            raise ContinueSignal()
        if fn=="return_value":
            val=self.eval(args[0]) if args else Value("void",None)
            raise ReturnSignal(val)
        if fn in self.functions:
            f=self.functions[fn]
            if len(args)!=len(f.parameters): raise FerricError(f"function {fn} expects {len(f.parameters)} argument(s), got {len(args)}")
            vals=[self.eval(a) for a in args]
            self.push()
            for name,val in zip(f.parameters,vals): self.scopes[-1][name]=Binding(val,False)
            try:
                try:
                    result=Value("void",None)
                    for stmt in f.body: result=self.eval(stmt)
                    return result
                except ReturnSignal as r: return r.value
            finally: self.pop()
        raise FerricError(f"unknown function {fn!r}",Token("ERROR",fn,node.line,node.column))

def load(path:Path):
    try: source=path.read_text(encoding="utf-8-sig")
    except OSError as e: raise FerricError(f"cannot read {path}: {e}")
    return source,Parser(lex(source)).program()



# Static semantic pass for the call-oriented FERRIC surface syntax.  It is
# deliberately conservative: dynamic/foreign calls are permitted, while the
# language's explicit declaration/reference/assignment forms are checked.
def analyze(tree: Node) -> dict[str, int]:
    scopes: list[dict[str, tuple[str, bool]]] = [{}]
    functions: dict[str, tuple[list[str], Node]] = {}
    stats = {"declarations": 0, "functions": 0, "references": 0, "assignments": 0}
    builtins = {
        "module", "scope", "declare", "value", "mutable", "visibility", "parameters",
        "define_function", "return_value", "if_true", "if_false", "while_loop", "for_range",
        "condition", "reference", "get_variable", "assign", "set_variable", "array", "array_new",
        "array_get", "get_index", "array_set", "set_index", "array_push", "array_pop", "length", "len",
        "map_new", "map_set", "map_get", "invoke", "function", "arguments", "effects", "result",
        "discard", "stdout.write", "stdout.write_line", "io.print", "io.println", "print", "println",
        "write", "write_line", "assert", "assert_equal", "sqrt", "abs", "min", "max", "pow",
        "floor", "ceil", "round", "hex", "binary", "type_of", "to_integer", "to_float", "to_text",
        "clock_ms", "break_loop", "continue_loop", "true", "false", "null"
    }
    def fail(msg: str, n: Node):
        raise FerricError(msg, Token("ERROR", "", n.line, n.column))
    def lookup(name: str, n: Node):
        for scope in reversed(scopes):
            if name in scope: return scope[name]
        fail(f"undeclared identifier {name!r}", n)
    def call_parts(n: Node):
        if n.kind != "call": return ("", [])
        return name_of(n.children[0]), n.children[1:]
    def literal_value(n: Node):
        if n.kind in ("string", "int", "float", "bool", "null"): return n.value
        return None
    def expr(n: Node) -> str:
        if n.kind in ("int", "float", "string", "bool", "null"):
            return {"int":"integer", "float":"float", "string":"text", "bool":"boolean", "null":"null"}[n.kind]
        if n.kind == "name":
            if n.value in SYMBOLS: return "symbol"
            # Bare identifiers are normally function/type/metadata names in this
            # syntax. Variable access must be explicit via reference("name").
            return "symbol"
        if n.kind == "member": return "symbol"
        if n.kind == "unary":
            t=expr(n.children[0]); op=n.value
            if op in ("-", "~") and t not in ("integer", "float", "any"): fail(f"operator {op} requires a numeric operand, got {t}", n)
            if op == "!" and t not in ("boolean", "integer", "any"): fail(f"operator ! requires a boolean-like operand, got {t}", n)
            return "boolean" if op == "!" else t
        if n.kind == "binary":
            a,b=expr(n.children[0]),expr(n.children[1]); op=n.value
            if op in ("==", "!=", "<", "<=", ">", ">=", "&&", "||"): return "boolean"
            if op == "+" and a == b == "text": return "text"
            if a not in ("integer", "float", "any") or b not in ("integer", "float", "any"):
                fail(f"operator {op} requires numeric operands, got {a} and {b}", n)
            return "float" if "float" in (a,b) or op=="/" else "integer"
        if n.kind == "block": stmt(n); return "void"
        if n.kind == "call":
            fn,args=call_parts(n)
            if fn in ("reference", "get_variable"):
                if not args: fail(f"{fn} requires a variable name", n)
                ident=literal_value(args[0])
                if not isinstance(ident,str): fail("variable reference name must be a string literal", args[0])
                typ,_=lookup(ident,n); stats["references"]+=1; return typ
            if fn in ("array", "array_new"): return "array"
            if fn in ("map_new",): return "map"
            if fn in ("length", "len", "array_push"): return "integer"
            if fn in ("array_get", "get_index", "map_get"): return "any"
            if fn in ("to_text", "hex", "binary"): return "text"
            if fn in ("to_integer", "floor", "ceil", "round"): return "integer"
            if fn in ("to_float", "sqrt"): return "float"
            if fn in ("assert", "assert_equal", "print", "println", "write", "write_line", "invoke", "array_set", "set_index", "map_set"): 
                for a in args: expr(a)
                return "void"
            if fn == "value":
                if len(args) != 2: fail("value(type, expression) requires two arguments", n)
                declared = name_of(args[0]) if args[0].kind in ("name", "member") else str(literal_value(args[0]))
                actual = expr(args[1])
                expected = ALIASES.get(declared, declared)
                if actual not in (expected, "any", "null") and expected != "any":
                    fail(f"value type mismatch: expected {expected}, got {actual}", args[1])
                return expected
            if fn == "condition":
                if len(args) != 1: fail("condition(expression) requires one argument", n)
                expr(args[0]); return "boolean"
            if fn in ("module", "scope", "mutable", "visibility", "parameters", "function", "arguments", "effects", "result", "discard"):
                for a in args: expr(a)
                return "metadata"
            if fn in functions:
                params,_=functions[fn]
                if len(args)!=len(params): fail(f"function {fn!r} expects {len(params)} argument(s), got {len(args)}",n)
                for a in args: expr(a)
                return "any"
            if fn in builtins or fn in ("stdout.write", "stdout.write_line", "io.print", "io.println"):
                for a in args: expr(a)
                return "any"
            # Unknown calls remain legal for foreign/platform functions; native
            # linking resolves them later. This avoids pretending semantic
            # analysis can know the entire external symbol universe.
            for a in args: expr(a)
            return "any"
        fail(f"unsupported syntax node {n.kind!r}", n)
        return "any"
    def stmt(n: Node):
        if n.kind == "program":
            for child in n.children or []: stmt(child)
            return
        if n.kind == "block":
            head=n.children[0] if n.children else None
            if head and head.kind=="call":
                fn,args=call_parts(head)
                if fn in ("module", "scope"):
                    scopes.append({})
                    try:
                        for child in n.children[1:]: stmt(child)
                    finally: scopes.pop()
                    return
                if fn == "define_function":
                    if len(args)<2 or args[0].kind!="string": fail("define_function requires a string name and parameters(...) ", head)
                    name=args[0].value; pnode=args[1]
                    if pnode.kind!="call" or name_of(pnode.children[0])!="parameters": fail("define_function second argument must be parameters(...) ",head)
                    params=[]
                    for a in pnode.children[1:]:
                        if a.kind!="string": fail("function parameter names must be string literals",a)
                        params.append(a.value)
                    if len(set(params))!=len(params): fail("duplicate function parameter",pnode)
                    if name in functions: fail(f"duplicate function {name!r}",head)
                    functions[name]=(params,n); stats["functions"]+=1
                    scopes.append({p:("any",False) for p in params})
                    try:
                        for child in n.children[1:]: stmt(child)
                    finally: scopes.pop()
                    return
                if fn in ("if_true", "if_false", "while_loop"):
                    for a in args: expr(a)
                    scopes.append({})
                    try:
                        for child in n.children[1:]: stmt(child)
                    finally: scopes.pop()
                    return
                if fn == "for_range":
                    if len(args) < 4 or args[0].kind != "string": fail("for_range(name, start, end, step) requires a string loop variable and three bounds", head)
                    for a in args[1:4]:
                        t=expr(a)
                        if t not in ("integer", "any"): fail("for_range bounds must be integers", a)
                    scopes.append({args[0].value:("integer",False)})
                    try:
                        for child in n.children[1:]: stmt(child)
                    finally: scopes.pop()
                    return
            for child in n.children or []: stmt(child)
            return
        if n.kind=="call":
            fn,args=call_parts(n)
            if fn=="declare":
                if len(args)<3: fail("declare(type, name, value(...)) requires at least three arguments",n)
                typ=name_of(args[0]) if args[0].kind in ("name","member") else literal_value(args[0])
                ident=literal_value(args[1])
                if not isinstance(ident,str): fail("declaration name must be a string literal",args[1])
                typ=ALIASES.get(str(typ),str(typ))
                if ident in scopes[-1]: fail(f"duplicate declaration {ident!r}",n)
                init=expr(args[2])
                if init not in (typ,"metadata","any","null") and typ!="any": fail(f"type mismatch: declared {typ}, initialized with {init}",args[2])
                mut=False
                for a in args[3:]:
                    if a.kind=="call" and name_of(a.children[0])=="mutable" and len(a.children)>1:
                        mut=literal_value(a.children[1]) is True
                scopes[-1][ident]=(typ,mut); stats["declarations"]+=1
                return
            if fn in ("assign", "set_variable"):
                if len(args)!=2: fail("assign(name, expression) requires two arguments",n)
                ident=literal_value(args[0])
                if not isinstance(ident,str): fail("assignment target must be a string literal",args[0])
                typ,mutable=lookup(ident,n)
                if not mutable: fail(f"cannot assign to immutable variable {ident!r}; declare it with mutable(true)",n)
                rhs=expr(args[1])
                if rhs not in (typ,"any","null") and typ!="any": fail(f"assignment type mismatch: {typ} cannot receive {rhs}",args[1])
                stats["assignments"]+=1; return
            if fn in ("return_value", "break_loop", "continue_loop"):
                for a in args: expr(a)
                return
            expr(n); return
        expr(n)
    stmt(tree)
    return stats


def main(argv=None):
    ap=argparse.ArgumentParser(prog="ferric",description="FERRIC reference toolchain")
    ap.add_argument("--version",action="version",version=f"FERRIC {VERSION}")
    ap.add_argument("--max-steps",type=int,default=1_000_000,help="execution step limit (default: 1,000,000)")
    sub=ap.add_subparsers(dest="command",required=True)
    for cmd in ("check","analyze","run","ast","tokens"):
        p=sub.add_parser(cmd); p.add_argument("source",type=Path)
    ns=ap.parse_args(argv)
    try:
        if ns.command=="tokens":
            source=ns.source.read_text(encoding="utf-8-sig")
            print(json.dumps([asdict(t) for t in lex(source)],indent=2,ensure_ascii=False)); return 0
        source,tree=load(ns.source)
        if ns.command=="ast": print(json.dumps(tree.json(),indent=2,ensure_ascii=False)); return 0
        if ns.command=="analyze":
            report=analyze(tree)
            print("FERRIC: semantic analysis passed (" + ", ".join(f"{k}={v}" for k,v in report.items()) + ")")
            return 0
        if ns.command=="check": analyze(tree)
        rt=Runtime(max_steps=max(1,ns.max_steps)); rt.eval(tree)
        if ns.command=="run":
            sys.stdout.write("".join(rt.output))
            if rt.output and not "".join(rt.output).endswith("\n"): sys.stdout.write("\n")
        else: print(f"FERRIC: check passed ({rt.declarations} declaration(s), {len(rt.functions)} function(s))")
        return 0
    except (FerricError,OSError) as e:
        print(f"FERRIC error: {e}",file=sys.stderr); return 1

if __name__=="__main__": raise SystemExit(main())
