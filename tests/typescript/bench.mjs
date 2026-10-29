import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
// The TypeScript frontend against node: each program of bench/ compiled by
// tsc (run on node) and by helder's compiler (native), both outputs checked equal,
// timed as the median of 5 fresh processes after one untimed run
// (startup and output included, compilation not).
const T='tests/typescript',dir='bin/typescript/bench';fs.mkdirSync(dir,{recursive:true});
function run(cmd,args){const r=spawnSync(cmd,args,{encoding:'utf8',timeout:600000});if(r.error)throw r.error;assert.equal(r.status,0,r.stderr+'\n'+r.stdout);return r.stdout;}
const compiler=run(process.execPath,['src/helder/typescript/build.mjs','--quiet']).trim();
function time(cmd,args,oracle){
    assert.equal(run(cmd,args),oracle);
    const samples=[];
    for(let i=0;i<5;i++){const start=process.hrtime.bigint();run(cmd,args);samples.push(Number(process.hrtime.bigint()-start)/1e6);}
    return samples.sort((a,b)=>a-b)[2];
}
const only=process.argv.slice(2);
console.log(`program        node (ms)  helder (ms)  ratio  (node ${process.version})`);
for(const file of fs.readdirSync(`${T}/bench`).filter(f=>f.endsWith('.ts')).sort()){
    const name=file.slice(0,-3);
    if(only.length&&!only.includes(name))continue;
    run(process.execPath,['node_modules/typescript/bin/tsc','--target','esnext','--strict','--skipLibCheck','--module','commonjs','--outDir',`${dir}/js`,`${T}/bench/${file}`]);
    run(compiler,[`${T}/bench/${file}`,'-o',`${dir}/${name}`]);
    const oracle=run(process.execPath,[`${dir}/js/${name}.js`]);
    const node=time(process.execPath,[`${dir}/js/${name}.js`],oracle),native=time(`${dir}/${name}`,[],oracle);
    console.log(`${name.padEnd(14)} ${node.toFixed(0).padStart(9)}  ${native.toFixed(0).padStart(11)}  ${(native/node).toFixed(2).padStart(5)}`);
}
