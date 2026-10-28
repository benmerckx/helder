import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
const dir='bin/bench';fs.mkdirSync(dir,{recursive:true});
function run(cmd,args){const r=spawnSync(cmd,args,{encoding:'utf8',timeout:120000});if(r.error)throw r.error;assert.equal(r.status,0,r.stderr+'\n'+r.stdout);return r.stdout;}
const report={node:process.version,platform:`${process.platform}-${process.arch}`,method:'Median of 5 fresh processes after 1 untimed run; includes process/VM startup and stdout. Compilation excluded.',programs:[]};
for(const file of fs.readdirSync('tests/bench').filter(f=>f.endsWith('.ts')).sort()){
    const name=file.slice(0,-3),src=`tests/bench/${file}`;
    run(process.execPath,['node_modules/typescript/bin/tsc','--target','esnext','--strict','--skipLibCheck','--outDir',`${dir}/js`,src]);
    for(const target of ['linux-x86_64','wasm32-wasi'])run('bin/tshx',[src,'--target',target,'-o',`${dir}/${name}-${target}`]);
    const oracle=run(process.execPath,[`${dir}/js/${name}.js`]);
    const times={};
    const commands={node:[process.execPath,[`${dir}/js/${name}.js`]],native:[`${dir}/${name}-linux-x86_64`,[]],wasi:[process.execPath,['tools/run-wasi.cjs',`${dir}/${name}-wasm32-wasi`]]};
    for(const [label,[cmd,args]] of Object.entries(commands)){
        assert.equal(run(cmd,args),oracle,`${name} ${label} warmup stdout`);
        const samples=[];
        for(let i=0;i<5;i++){const start=process.hrtime.bigint();assert.equal(run(cmd,args),oracle);samples.push(Number(process.hrtime.bigint()-start)/1e6);}
        samples.sort((a,b)=>a-b);times[label]=Number(samples[2].toFixed(3));
    }
    const coverage=JSON.parse(run('bin/tshx',['coverage',src]));
    report.programs.push({name,stdout:oracle.trim(),medianMs:times,coverage});
    console.log(`${name}: ${JSON.stringify(times)}`);
}
fs.writeFileSync(`${dir}/results.json`,JSON.stringify(report,null,2)+'\n');
console.log(report.method);
