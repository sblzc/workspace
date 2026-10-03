// Validate the edited cordis.patch.yml the same way the loader does:
// register the !!js custom type, parse, then evaluate the expression exactly
// as cordis-plugin-loader does (new Function('ctx','expr','with(ctx){return eval(expr)}')).
// Also prove the expression works inside the constrained evaluation shape the
// loader builds, and that no plaintext token lands in the config file.
//
// ASCII only. Run: node _yamlcheck.mjs
import { readFileSync } from 'node:fs'

const YAML_PATH = 'C:/Users/AlanL/.dsh/profiles/web/cordis.patch.yml'
const doc = readFileSync(YAML_PATH, 'utf8')

const yaml = await import(
  'file:///C:/Users/AlanL/AppData/Roaming/npm/node_modules/@deepseek-ai/dsh/node_modules/js-yaml/index.js'
)

const JsExpr = new yaml.Type('tag:yaml.org,2002:js', {
  kind: 'scalar',
  construct: data => ({ __jsExpr: data }),
})
const SCHEMA = yaml.DEFAULT_SCHEMA.extend([JsExpr])

let parsed
try {
  parsed = yaml.load(doc, { schema: SCHEMA })
  console.log('YAML parse: OK')
} catch (e) {
  console.log('YAML parse: FAIL')
  console.log(String(e.message).slice(0, 2000))
  process.exit(1)
}

console.log('top-level entries:', Array.isArray(parsed) ? parsed.length : typeof parsed)

const found = []
for (const entry of parsed) {
  for (const row of entry?.insert ?? []) found.push(row)
}
console.log('insert rows:', found.map(r => r.id).join(', '))

const gh = found.find(r => r.id === 'mcp-github')
if (!gh) { console.log('mcp-github row: NOT FOUND'); process.exit(1) }
console.log('\nmcp-github row: found')
console.log('  name       :', gh.name)
console.log('  serverName :', gh.config.serverName)
console.log('  transport  :', gh.config.transport)
console.log('  url        :', gh.config.url)
console.log('  failLoud   :', gh.config.failOnStartupError)

const auth = gh.config.headers.Authorization
const isJs = auth && typeof auth === 'object' && '__jsExpr' in auth
console.log('  Authorization is !!js node:', isJs)
console.log('  expression (first 120):', String(auth?.__jsExpr).slice(0, 120))

// Evaluate exactly like the loader does.
const evaluate = new Function('ctx', 'expr', 'with (ctx) { return eval(expr) }')

console.log('\n  eval with the real token file present:')
try {
  const v = evaluate({}, auth.__jsExpr)
  console.log('    ->', v.slice(0, 22) + '...', '(typeof', typeof v + ', len ' + v.length + ')')
  console.log('    schema check (z.dict(String)):', typeof v === 'string' && v.startsWith('Bearer ') ? 'PASS' : 'FAIL')
} catch (e) {
  console.log('    -> THREW:', e.message)
  console.log('    schema check: FAIL (connector would not start)')
}

console.log('\n  eval with the token file hidden (simulates a missing token):')
const realRead = readFileSync
const fsmod = await import('node:fs')
const orig = fsmod.default.readFileSync
fsmod.default.readFileSync = (p, ...rest) => {
  if (String(p).includes('.github-token')) { const e = new Error('ENOENT'); e.code = 'ENOENT'; throw e }
  return orig(p, ...rest)
}
try {
  const v = evaluate({}, auth.__jsExpr)
  console.log('    -> returned', JSON.stringify(v), '<-- failOnStartupError would catch this')
} catch (e) {
  console.log('    -> THREW:', e.message)
}
fsmod.default.readFileSync = realRead === orig ? orig : orig

// The config file itself must carry no token.
const m = doc.match(/github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}/)
console.log('\n  plaintext token in cordis.patch.yml:', m ? 'FOUND ' + m[0].slice(0, 20) + '...' : 'NONE (clean)')
