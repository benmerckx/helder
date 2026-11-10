// helder's web page passes its query to the program as arguments
// (src/helder/cli/page.html, pageArgs): ?proto=a&screen=2&fast gives
// --proto a --screen 2 --fast; gfx stays the page's own.
//   node tests/cli/page-args.mjs
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const page = readFileSync(new URL('../../src/helder/cli/page.html', import.meta.url), 'utf8');
const source = /function pageArgs\(search\) \{[\s\S]*?\n\}/.exec(page);
assert.ok(source, 'page.html has pageArgs');
const pageArgs = new Function(source[0] + '\nreturn pageArgs;')();
assert.deepEqual(pageArgs(''), []);
assert.deepEqual(pageArgs('?proto=a&screen=2'), ['--proto', 'a', '--screen', '2']);
assert.deepEqual(pageArgs('?fast&gfx=webgl2'), ['--fast']);
assert.deepEqual(pageArgs('?name=a%20b'), ['--name', 'a b']);
console.log('ok   page arguments from the query');
