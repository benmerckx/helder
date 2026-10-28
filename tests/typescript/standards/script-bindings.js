"use strict";
var value=1;
var value=2;
var value;
if(value!==2)throw new Error("var redeclaration lost value");
if(this!==globalThis || (()=>this)()!==globalThis)throw new Error("Script this must be globalThis");
function strictThis(){return this;}
if(strictThis()!==undefined)throw new Error("Strict function this must be undefined");
if(Object.getOwnPropertyDescriptor(this,"ArrayBuffer").value!==ArrayBuffer)throw new Error("Global descriptor");
console.log("Script binding checks passed");
