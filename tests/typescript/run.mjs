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
// (util.inspect's symbol keys: Node 24 writes Symbol(k): v, earlier ones
// [Symbol(k)]: v; helder's one way: both outputs written one way, so the
// oracle's version does not matter)
// (and Float16Array, DataView's float16s: Node 24's, behind V8's flag before)
const oracleFlags=typeof Float16Array==='undefined'?['--js-float16array']:[];
function inspected(s) {return s.replace(/\[(Symbol\((?:[^()]|\([^()]*\))*\))\]: /g,'$1: ');}
function ok(r,what) {assert.equal(r.status,0,`${what}\n${r.stdout}\n${r.stderr}`);}
const targets=['linux-x86_64','wasm32-wasi'];
const files=fs.readdirSync(`${T}/cases`).filter(f=>f.endsWith('.ts')).sort();
let passed=0;
for(const file of files) {
    const stem=path.basename(file,'.ts');
    const reference=run(process.execPath,[...tsc,'--module','commonjs','--outDir',`${dir}/js`,`${T}/cases/${file}`]); ok(reference,'reference tsc');
    // (a case of what only a newer Node has, Promise.try, RegExp.escape,
    // Error.isError: its output as Node 24 writes it beside it, <stem>.out,
    // the oracle where this Node cannot run it, checked against it where it can)
    const saved=`${T}/cases/${stem}.out`;
    let oracle=run(process.execPath,[...oracleFlags,`${dir}/js/${stem}.js`]);
    if(fs.existsSync(saved)) {
        const want=fs.readFileSync(saved,'utf8');
        if(oracle.status!==0) {console.log(`(${stem}: node ${process.version} cannot run it, ${stem}.out the oracle)`);oracle={status:0,stdout:want};}
        else assert.equal(inspected(oracle.stdout),inspected(want),`${stem}.out is not what node writes`);
    }
    ok(oracle,'reference node');
    for(const target of targets) {
        const out=`${dir}/${stem}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
        const compiled=run(compiler,[`${T}/cases/${file}`,'--roundtrip-ir','--target',target,'-o',out,'--dump-ir',`${out}.ir`]);
        ok(compiled,`${stem} compile ${target}`);
        const launchers=target==='linux-x86_64'?[[out,[]]]:[[process.execPath,[`${T}/run-wasi.cjs`,out]]];
        for(const [cmd,args] of launchers) {
            const result=run(cmd,args);
            assert.equal(result.status,oracle.status,`${stem} exit ${target} ${args[0]??''}\n${result.stderr}`);
            assert.equal(inspected(result.stdout),inspected(oracle.stdout),`${stem} stdout ${target} ${args[0]??''}`);
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
    const oracle=run(process.execPath,[...oracleFlags,`${out}/main.js`]); ok(oracle,'reference node');
    for(const target of targets) {
        const binary=`${dir}/module-${name}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
        ok(run(compiler,[`${T}/modules/${name}/main.ts`,'--roundtrip-ir','--target',target,'-o',binary]),`${name} compile ${target}`);
        const launcher=target==='linux-x86_64'?[binary,[]]:[process.execPath,[`${T}/run-wasi.cjs`,binary]];
        const result=run(launcher[0],launcher[1]);
        assert.equal(result.status,oracle.status,`module ${name} exit ${target}\n${result.stderr}`);
        assert.equal(inspected(result.stdout),inspected(oracle.stdout),`module ${name} stdout ${target}`);
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
// helder's declaration files, and the tests' (test-renderer.d.ts): as its
// Haxe types make them (helder.typescript.api.Declarations)
ok(run(process.execPath,['src/helder/typescript/api/declarations.mjs','--check']),'helder\'s declarations');
ok(run(process.execPath,['src/helder/typescript/api/declarations.mjs','--check','--cp','tests/view','--cp','tests/ui','TestTypeScript','UiTypeScript']),'the tests\' declarations');
ok(run(process.execPath,['src/helder/typescript/api/declarations.mjs','--check','--cp',`${T}/platform`,'PlatformTypeScript']),'platform/win32.d.ts');
console.log('PASS declarations');
// Programs calling helder's Haxe API (and TSX), rendering headless with
// tests/view's TestRenderer: their output checked against <name>.out
for(const file of fs.readdirSync(`${T}/helder`).filter(f=>/\.tsx?$/.test(f)&&!f.endsWith('.d.ts')).sort())for(const target of targets) {
    const stem=file.replace(/\.tsx?$/,''),out=`${dir}/helder-${stem}${target!=='linux-x86_64'?`-${target}.wasm`:''}`;
    ok(run(compiler,[`${T}/helder/${file}`,'--cp','tests/view','--cp','tests/ui','--roundtrip-ir','--target',target,'-o',out]),`${file} compile ${target}`);
    const r=target==='linux-x86_64'?run(out,[]):run(process.execPath,[`${T}/run-wasi.cjs`,out]);ok(r,`${file} ${target}`);
    assert.equal(r.stdout,fs.readFileSync(`${T}/helder/${stem}.out`,'utf8'),`${file} stdout ${target}`);
    console.log(`PASS helder ${file} ${target}`);
}
// helder/platform's constants folded as Haxe's Platform.os() is: platform/main.ts
// and Main.hx built for Linux (glibc's dynamic mode, where a C function of a
// shared library is an import) and wasm32-wasi, their Windows branch
// (kernel32's GetTickCount64) not in the binary; the same TS with a condition
// that is no constant names it (the check's control)
{
    const P=`${T}/platform`,has=(f,s)=>fs.readFileSync(f).includes(Buffer.from(s));
    for(const target of targets) {
        const glibc=target==='linux-x86_64'?['-D','hxmc.libc=glibc']:[];
        const ts=`${dir}/platform-ts${target!=='linux-x86_64'?'.wasm':''}`,hx=`${dir}/platform-hx${target!=='linux-x86_64'?'.wasm':''}`;
        ok(run(compiler,[`${P}/main.ts`,'--cp',P,'--target',target,...glibc,'-o',ts]),`platform/main.ts compile ${target}`);
        ok(run(compiler,['-cp',P,'-main','Main','-D',`hxmc.target=${target}`,...glibc,'--custom-target',`hxmc=${hx}`]),`platform/Main.hx compile ${target}`);
        const os=target==='linux-x86_64'?'linux':'wasi';
        const exec=f=>target==='linux-x86_64'?run(f,[]):run(process.execPath,[`${T}/run-wasi.cjs`,f]);
        const a=exec(ts);ok(a,`platform/main.ts ${target}`);
        assert.equal(a.stdout,`not windows: ${os} ${target}\n${os==='wasi'?'no x86-64 code':'x86-64'}\na Linux or a WASI build\n`,`platform/main.ts stdout ${target}`);
        const h=exec(hx);ok(h,`platform/Main.hx ${target}`);
        assert.equal(h.stdout,`not windows: ${os}\n`,`platform/Main.hx stdout ${target}`);
        for(const f of [ts,hx]) assert.ok(!has(f,'GetTickCount64')&&!has(f,'kernel32'),`${f}: a Windows branch linked for ${target}`);
        console.log(`PASS platform ${target} (main.ts ${Math.round(fs.statSync(ts).size/1024)} KB, Main.hx ${Math.round(fs.statSync(hx).size/1024)} KB: no GetTickCount64)`);
    }
    if(process.platform==='linux') {
        const src=fs.readFileSync(`${P}/main.ts`,'utf8').replace('if (platform.os === "windows")','if (Math.random() > 2)');
        fs.writeFileSync(`${P}/control.ts`,src);
        try {
            const c=`${dir}/platform-control`;
            ok(run(compiler,[`${P}/control.ts`,'--cp',P,'-D','hxmc.libc=glibc','-o',c]),'platform/control.ts compile');
            assert.ok(has(c,'GetTickCount64'),'the control names GetTickCount64');
        } finally {fs.rmSync(`${P}/control.ts`);}
        console.log('PASS platform control (a condition that is no constant: GetTickCount64 linked)');
    }
}
// helder/native's definitions: native.mjs (native.c, objc, com, jni where
// their systems are; refused elsewhere)
ok(run(process.execPath,[`${T}/native.mjs`]),'helder/native\'s checks (native.mjs)');
console.log('PASS native (native.mjs)');
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
// Definitions (src/helder/compiler/DESIGN.md) in both languages:
// definitions/<name>.ts (or .tsx) and the Haxe program <Name>.hx, built natively and
// as wasm32-wasi, print the same (a shader's text in all four languages,
// its writers' bytes); each pair of definitions/reject is refused by both
// with the same diagnostic (expect)
const D=`${T}/definitions`;
for(const file of fs.readdirSync(D).filter(f=>/\.tsx?$/.test(f)&&f!=='print.ts').sort())for(const target of targets) {
    const stem=file.replace(/\.tsx?$/,''),main=stem[0].toUpperCase()+stem.slice(1),wasm=target!=='linux-x86_64';
    // (a case for some targets only: `// targets: <t>,...` in it)
    const only=fs.readFileSync(`${D}/${file}`,'utf8').match(/^\/\/ targets: (.*)$/m)?.[1].split(',');
    if(only&&!only.includes(target))continue;
    const ts=`${dir}/def-${stem}${wasm?'.wasm':''}`,hx=`${dir}/def-${main}${wasm?'.wasm':''}`;
    ok(run(compiler,[`${D}/${file}`,'-D','helder.gfx.shaders=all','--target',target,'-o',ts]),`${file} compile ${target}`);
    ok(run(compiler,['-cp','src','-cp',D,'-main',main,'-D','helder.gfx.shaders=all','-D',`hxmc.target=${target}`,'--custom-target',`hxmc=${hx}`]),`${main}.hx compile ${target}`);
    const exec=f=>wasm?run(process.execPath,[`${T}/run-wasi.cjs`,f]):run(f,[]);
    const a=exec(ts),b=exec(hx);ok(a,`${file} ${target}`);ok(b,`${main}.hx ${target}`);
    assert.ok(a.stdout.length>0,`${file} printed nothing`);
    assert.equal(a.stdout,b.stdout,`${file} and ${main}.hx print alike ${target}`);
    console.log(`PASS definition ${file} = ${main}.hx ${target}`);
}
for(const file of fs.readdirSync(`${D}/reject`).filter(f=>/\.tsx?$/.test(f)).sort()) {
    const main='Reject'+file.replace(/\.tsx?$/,'').split('-').map(p=>p[0].toUpperCase()+p.slice(1)).join('');
    const expect=f=>fs.readFileSync(f,'utf8').match(/expect: (.*)$/m)[1];
    const want=expect(`${D}/reject/${file}`);
    assert.equal(expect(`${D}/reject/${main}.hx`),want,`${file} and ${main}.hx expect the same diagnostic`);
    const out=`${dir}/def-reject`;fs.rmSync(out,{force:true});
    const a=run(compiler,[`${D}/reject/${file}`,'-o',out]);
    assert.notEqual(a.status,0,`${file} should be rejected`);
    assert.ok(a.stderr.includes(want),`${file} should report ${want}, got ${a.stderr}`);
    // (typed for hxmc: a job's checks are its)
    const b=run(compiler,['-cp','src','-cp',`${D}/reject`,'-main',main,'--custom-target',`hxmc=${out}-hx`]);
    assert.notEqual(b.status,0,`${main}.hx should be rejected`);
    assert.ok((b.stdout+b.stderr).includes(want),`${main}.hx should report ${want}, got ${b.stdout}${b.stderr}`);
    console.log(`PASS definition rejected: ${file}, ${main}.hx`);
}
// helder/gfx's TypeScript, as typescript.mjs writes it
ok(run(process.execPath,['src/helder/gfx/typescript.mjs','--check']),'src/helder/gfx/index.ts');
// The CLI end to end: TypeScript entries built and run by `helder run` (a file, a directory)
for(const entry of ['examples/ts-hello/main.ts','examples/ts-hello']) {
    const r=run(process.execPath,['src/helder/cli/run.mjs','run',entry]);ok(r,`helder run ${entry}`);
    assert.match(r.stdout,/1\. hello, helder\n2\. hello, TypeScript\ndone\n/,`helder run ${entry}`);
    console.log(`PASS helder run ${entry}`);
}
// `helder dev` of examples/ts-ticker (a copy): an edit to label.ts rebuilds
// it and swaps it in, its signal's count going on (fast refresh's keys),
// its builds counted by keep (a value kept by its key)
{
    const work=`${dir}/ticker`;fs.mkdirSync(work,{recursive:true});
    for(const f of ['main.ts','label.ts'])fs.copyFileSync(`examples/ts-ticker/${f}`,`${work}/${f}`);
    const {spawn}=await import('node:child_process');
    const p=spawn(process.execPath,['src/helder/cli/run.mjs','dev',`${work}/main.ts`],{stdio:['ignore','pipe','pipe'],detached:true});
    let out='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>out+=d);
    const until=async(re,ms)=>{const end=Date.now()+ms;while(Date.now()<end){const m=out.match(re);if(m)return m;await new Promise(r=>setTimeout(r,50));}return null;};
    const before=await until(/tick 3\n/,120000);
    fs.writeFileSync(`${work}/label.ts`,fs.readFileSync(`${work}/label.ts`,'utf8').replace('tick','TOCK'));
    const after=await until(/TOCK (\d+)\n/,60000);
    // (its group: the CLI, its compilation server, the program)
    const stop=sig=>{try{process.kill(-p.pid,sig);}catch{}};
    stop('SIGINT');await new Promise(r=>setTimeout(r,1000));stop('SIGKILL');
    assert.ok(before&&after,`helder dev examples/ts-ticker: no reload seen\n${out}`);
    assert.ok(Number(after[1])>=3,`helder dev examples/ts-ticker: the count started over (TOCK ${after[1]} after tick 3)\n${out}`);
    assert.match(out,/build 1\n[^]*build 2\n/,`helder dev examples/ts-ticker: keep's count of builds not kept\n${out}`);
    console.log(`PASS helder dev examples/ts-ticker (tick 3 ... TOCK ${after[1]}, build 1 ... build 2)`);
}
console.log(`${passed}/${(files.length+programs.length+standards.length)*targets.length} checks passed (tsc + node; native, wasm32-wasi)`);
