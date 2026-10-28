{
function throws(fn:()=>unknown){try{fn();console.log("no error");}catch(e:any){console.log(e.name);}}
const b=new ArrayBuffer(32), v=new DataView(b,2,24);
console.log(b.byteLength,b.maxByteLength,b.resizable,b.detached,v.buffer===b,v.byteOffset,v.byteLength,ArrayBuffer.isView(v),ArrayBuffer.isView(b));
for(let i=0;i<v.byteLength;i++)if(v.getUint8(i)!==0)throw new Error("Not zero initialized");
v.setUint32(0,0x12345678);console.log(v.getUint8(0),v.getUint8(3),v.getUint32(0,true));
v.setInt32(1,-123456789,true);console.log(v.getInt32(1,true),v.getUint32(1,true));
v.setInt8(0,255);v.setUint8(1,257);v.setInt16(2,65535);v.setUint16(4,65537,true);
console.log(v.getInt8(0),v.getUint8(1),v.getInt16(2),v.getUint16(4,true));
for(const n of [0,-0,1,-2.5,Math.PI,65504,65520,2**-24,2**-25,Infinity,-Infinity,NaN])for(const little of [false,true]){
 v.setFloat16(1,n,little);v.setFloat32(5,n,little);v.setFloat64(11,n,little);
 const a=v.getFloat16(1,little),c=v.getFloat32(5,little),d=v.getFloat64(11,little);
 if(!Object.is(a,Math.f16round(n)) || !Object.is(c,Math.fround(n)) || !Object.is(d,n))throw new Error("Float mismatch");
}
console.log("floating point byte roundtrips passed");
const sliced=b.slice(2,7);console.log(sliced.byteLength,new DataView(sliced).getUint8(0),sliced instanceof ArrayBuffer);
const r=new ArrayBuffer(8,{maxByteLength:16}), track=new DataView(r,2),fixed=new DataView(r,2,4);
track.setUint8(0,99);r.resize(4);console.log(track.byteLength,track.getUint8(0));throws(()=>fixed.byteLength);
r.resize(12);console.log(track.byteLength,fixed.byteLength,track.getUint8(2));
const moved=r.transfer(14);console.log(r.detached,r.byteLength,r.maxByteLength,r.resizable,moved.resizable,moved.maxByteLength,moved.byteLength,new DataView(moved).getUint8(2));
console.log(track.buffer===r,ArrayBuffer.isView(track));throws(()=>track.getUint8(0));throws(()=>track.byteOffset);
const fixedMoved=moved.transferToFixedLength(18);console.log(moved.detached,fixedMoved.resizable,fixedMoved.maxByteLength,fixedMoved.byteLength);
for(const fn of [()=>new ArrayBuffer(-1),()=>new ArrayBuffer(4,{maxByteLength:3}),()=>b.resize(2),()=>new DataView(b,33),()=>v.getUint32(22),()=>v.setFloat64(-1,0),()=>r.slice(),()=>r.resize(1),()=>r.transfer(),()=>DataView.prototype.getInt8.call({},0)])throws(fn);
class SubBuffer extends ArrayBuffer {}const sub=new SubBuffer(4);console.log(sub instanceof SubBuffer,sub.slice() instanceof SubBuffer,sub.transfer() instanceof SubBuffer);
class CustomBuffer extends ArrayBuffer {static get [Symbol.species](){return ArrayBuffer;}}console.log(new CustomBuffer(3).slice() instanceof CustomBuffer);
let order="";const ordered=new ArrayBuffer({valueOf(){order+="L";return 3;}} as any,{get maxByteLength(){order+="M";return 5;}});console.log(order,ordered.byteLength,ordered.maxByteLength);
const detached=new ArrayBuffer(1);let valueCalled=0;const dv=new DataView(detached);detached.transfer();throws(()=>dv.setInt8(0,{valueOf(){valueCalled++;return 1;}} as any));console.log(valueCalled);
console.log(Object.prototype.toString.call(b),Object.prototype.toString.call(v),ArrayBuffer[Symbol.species]===ArrayBuffer);
}
