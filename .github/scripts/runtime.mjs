// helder's runtime modules (src/helder/<package>/*.mjs) as helder.run's
// POST /api/runtime takes them: {files: [{path: "helder/<package>/<name>.mjs", sha256}]}
// (run.yml registers them before publishing the examples: helder.run runs
// only runtime files it knows)
import { createHash } from 'node:crypto'
import { readdirSync, readFileSync, statSync } from 'node:fs'
const files = []
for (const pkg of readdirSync('src/helder')) {
  const dir = `src/helder/${pkg}`
  if (!statSync(dir).isDirectory()) continue
  for (const f of readdirSync(dir).filter((f) => f.endsWith('.mjs')))
    files.push({ path: `helder/${pkg}/${f}`, sha256: createHash('sha256').update(readFileSync(`${dir}/${f}`)).digest('hex') })
}
process.stdout.write(JSON.stringify({ files }))
