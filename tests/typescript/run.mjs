import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';
// The TypeScript frontend's checks (bun run test typescript): every program
// of cases/ and modules/ compiled by tsc and run on node, then compiled by
// helder's compiler natively and as wasm32-wasi, their outputs compared; standards/
// throw on a mismatch themselves; reject/ must fail with a diagnostic.
const T='tests/typescript';
const dir=`bin/typescript/run-${process.pid}`; fs.mkdirSync(dir,{recursive:true});
const built=spawnSync(process.execPath,['src/helder/compiler/build.mjs'],{encoding:'utf8',stdio:['ignore','pipe','inherit']});
if(built.status!==0)process.exit(1);
const compiler=built.stdout.trim();
// (the IR checks: the verifier, the text form and its golden file)
const hxmc=spawnSync(process.execPath,['src/helder/compiler/build.mjs','--sources','--quiet'],{encoding:'utf8'}).stdout.trim();
const launcher='node_modules/@hxmc/cli/hxmc/bootstrap/haxe.mjs';
ok(run(process.execPath,[launcher,'-cp','src','-cp',T,'-cp',`${hxmc}/haxe/src`,'-cp',`${hxmc}/hxmc/src`,'-main','IrTests','-D','hih_no_generators','-D','disable-parallelism','--custom-target',`hxmc=${dir}/ir-tests`]),'IR checks build');
const ir=run(`${dir}/ir-tests`,process.env.BLESS?['--write-golden']:[]);ok(ir,'IR checks');process.stdout.write(ir.stdout);
const tsc=['node_modules/typescript/bin/tsc','--target','esnext','--strict','--skipLibCheck'];
function run(cmd,args) {const r=spawnSync(cmd,args,{encoding:'utf8',timeout:120000});if(r.error)throw r.error;return r;}
function ok(r,what) {assert.equal(r.status,0,`${what}\n${r.stdout}\n${r.stderr}`);}
const targets=['linux-x86_64','wasm32-wasi'];
const files=fs.readdirSync(`${T}/cases`).filter(f=>f.endsWith('.ts')).sort();
let passed=0;
for(const file of files) {
    const stem=path.basename(file,'.ts');
    const reference=run(process.execPath,[...tsc,'--module','commonjs','--outDir',`${dir}/js`,`${T}/cases/${file}`]); ok(reference,'reference tsc');
    const oracle=run(process.execPath,[`${dir}/js/${stem}.js`]); ok(oracle,'reference node');
    for(const target of targets) {
        const out=`${dir}/${stem}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
        const compiled=run(compiler,[`${T}/cases/${file}`,'--roundtrip-ir','--target',target,'-o',out,'--dump-ir',`${out}.ir`]);
        ok(compiled,`${stem} compile ${target}`);
        const launchers=target==='linux-x86_64'?[[out,[]]]:[[process.execPath,[`${T}/run-wasi.cjs`,out]]];
        for(const [cmd,args] of launchers) {
            const result=run(cmd,args);
            assert.equal(result.status,oracle.status,`${stem} exit ${target} ${args[0]??''}\n${result.stderr}`);
            assert.equal(result.stdout,oracle.stdout,`${stem} stdout ${target} ${args[0]??''}`);
        }
        console.log(`PASS ${stem} ${target}`); passed++;
    }
}
// Multi-file programs: tests/modules/<name>/main.ts, referenced as ES modules.
const programs=fs.existsSync(`${T}/modules`)?fs.readdirSync(`${T}/modules`).sort():[];
for(const name of programs) {
    const out=`${dir}/modules/${name}`;fs.mkdirSync(out,{recursive:true});
    fs.writeFileSync(`${out}/package.json`,'{"type":"module"}');
    const reference=run(process.execPath,[...tsc,'--module','esnext','--moduleResolution','bundler','--outDir',out,`${T}/modules/${name}/main.ts`]); ok(reference,'reference tsc');
    const oracle=run(process.execPath,[`${out}/main.js`]); ok(oracle,'reference node');
    for(const target of targets) {
        const binary=`${dir}/module-${name}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
        ok(run(compiler,[`${T}/modules/${name}/main.ts`,'--roundtrip-ir','--target',target,'-o',binary]),`${name} compile ${target}`);
        const launcher=target==='linux-x86_64'?[binary,[]]:[process.execPath,[`${T}/run-wasi.cjs`,binary]];
        const result=run(launcher[0],launcher[1]);
        assert.equal(result.status,oracle.status,`module ${name} exit ${target}\n${result.stderr}`);
        assert.equal(result.stdout,oracle.stdout,`module ${name} stdout ${target}`);
        console.log(`PASS module ${name} ${target}`); passed++;
    }
}

// Self-checking programs for current specified behavior where Node, the
// oracle, still differs: each throws on a mismatch.
const standards=fs.readdirSync(`${T}/standards`).filter(f=>/\.[jt]s$/.test(f)).sort();
for(const file of standards)for(const target of targets) {
    const out=`${dir}/standard-${file}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
    ok(run(compiler,[`${T}/standards/${file}`,'--roundtrip-ir','--target',target,'-o',out]),`${file} compile ${target}`);
    ok(target==='linux-x86_64'?run(out,[]):run(process.execPath,[`${T}/run-wasi.cjs`,out]),`${file} ${target}`);
    console.log(`PASS standard ${file} ${target}`); passed++;
}
for(const file of fs.readdirSync(`${T}/reject`).filter(f=>f.endsWith('.ts')).sort()) {
    const out=`${dir}/reject-${path.basename(file,'.ts')}`; fs.rmSync(out,{force:true});
    const r=run(compiler,[`${T}/reject/${file}`,'-o',out]);
    assert.notEqual(r.status,0,`${file} should be rejected`);
    assert.match(r.stderr,/TS(HX)?[0-9]+:/,`${file} needs a diagnostic code`);
    const expected=fs.readFileSync(`${T}/reject/${file}`,'utf8').match(/expect: (.*?)(?: \*\/)?$/m)?.[1];
    if(expected)assert.ok(r.stderr.includes(expected),`${file} should report ${expected}, got ${r.stderr}`);
    assert.equal(fs.existsSync(out),false,`${file} must not emit an executable`);
    console.log(`PASS diagnostic ${file}`);
}
// Programs calling helder's Haxe API (and TSX), rendering headless with
// tests/view's TestRenderer: their output checked against <name>.out
for(const file of fs.readdirSync(`${T}/helder`).filter(f=>/\.tsx?$/.test(f)&&!f.endsWith('.d.ts')).sort())for(const target of targets) {
    const stem=file.replace(/\.tsx?$/,''),out=`${dir}/helder-${stem}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
    ok(run(compiler,[`${T}/helder/${file}`,'--cp','tests/view','--roundtrip-ir','--target',target,'-o',out]),`${file} compile ${target}`);
    const r=target==='linux-x86_64'?run(out,[]):run(process.execPath,[`${T}/run-wasi.cjs`,out]);ok(r,`${file} ${target}`);
    assert.equal(r.stdout,fs.readFileSync(`${T}/helder/${stem}.out`,'utf8'),`${file} stdout ${target}`);
    console.log(`PASS helder ${file} ${target}`);
}
// Programs whose values their types do not describe: compiled, then stopped
// where such a value enters a typed slot (TSHX100, at the line of expect)
for(const file of fs.readdirSync(`${T}/diverge`).filter(f=>f.endsWith('.ts')).sort())for(const target of targets) {
    const out=`${dir}/diverge-${path.basename(file,'.ts')}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
    ok(run(compiler,[`${T}/diverge/${file}`,'--target',target,'-o',out]),`${file} compile ${target}`);
    const r=target==='linux-x86_64'?run(out,[]):run(process.execPath,[`${T}/run-wasi.cjs`,out]);
    const expected=fs.readFileSync(`${T}/diverge/${file}`,'utf8').match(/expect: (.*)$/m)[1];
    assert.notEqual(r.status,0,`${file} should diverge ${target}`);
    assert.ok(r.stderr.includes(expected),`${file} should report ${expected} ${target}, got ${r.stderr}`);
    console.log(`PASS diverge ${file} ${target}`);
}
// Projects with a tsconfig.json: built and run, or refused at the option's line (expect)
for(const name of fs.readdirSync(`${T}/configs`).sort()) {
    const d=`${T}/configs/${name}`,out=`${dir}/config-${name}`;
    const r=run(compiler,[`${d}/main.ts`,'-o',out]);
    if(fs.existsSync(`${d}/expect`)) {
        const expected=fs.readFileSync(`${d}/expect`,'utf8').trim();
        assert.notEqual(r.status,0,`${name} should be refused`);
        assert.ok(r.stderr.includes(expected),`${name} should report ${expected}, got ${r.stderr}`);
    } else {
        ok(r,`${name} compile`);
        ok(run(out,[]),`${name} run`);
    }
    console.log(`PASS config ${name}`);
}
// The CLI end to end: TypeScript entries built and run by `helder run` (a file, a directory)
for(const entry of ['examples/ts-hello/main.ts','examples/ts-hello']) {
    const r=run(process.execPath,['src/helder/cli/run.mjs','run',entry]);ok(r,`helder run ${entry}`);
    assert.match(r.stdout,/1\. hello, helder\n2\. hello, TypeScript\ndone\n/,`helder run ${entry}`);
    console.log(`PASS helder run ${entry}`);
}
console.log(`${passed}/${(files.length+programs.length+standards.length)*targets.length} checks passed (tsc + node; native, wasm32-wasi)`);
