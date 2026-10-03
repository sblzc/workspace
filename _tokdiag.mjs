// Diagnose exactly what the current token can and cannot do.
// The git push failure ("Permission to sblzc/workspace.git denied") is
// ambiguous; the API tells us which of the two possible causes it is:
//   (a) the repo is not in the token's Selected repositories, so it cannot
//       even see it  -> GET /repos returns 404
//   (b) the repo IS selected but Contents is set to read-only
//                    -> GET /repos returns 200 with push:false
// ASCII only. Run: node _tokdiag.mjs
import { readFileSync } from 'node:fs'

const token = readFileSync('D:/radio/.github-token', 'utf8').trim()
const H = {
  Authorization: `Bearer ${token}`,
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'dsh-token-diagnostic',
}

async function api(path, method = 'GET', body) {
  const res = await fetch(`https://api.github.com${path}`, {
    method,
    headers: { ...H, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(30000),
  })
  let json = null
  try { json = await res.json() } catch {}
  return { status: res.status, json }
}

console.log('=== who is this token? ===')
const me = await api('/user')
console.log('  status:', me.status)
if (me.status !== 200) {
  console.log('  body:', JSON.stringify(me.json).slice(0, 400))
  console.log('\n  => the token itself is rejected. It is expired, revoked, or malformed.')
  process.exit(1)
}
console.log('  login:', me.json.login, ' id:', me.json.id)

console.log('\n=== can it SEE sblzc/workspace? ===')
const repo = await api('/repos/sblzc/workspace')
console.log('  status:', repo.status)
if (repo.status === 404) {
  console.log('  => CAUSE (a): the repo is NOT in the token\'s Selected repositories.')
  console.log('     A fine-grained token cannot see repositories that were not selected')
  console.log('     at creation time, so every operation on it looks like "denied".')
} else if (repo.status === 200) {
  console.log('  default_branch:', repo.json.default_branch)
  console.log('  size          :', repo.json.size)
  console.log('  permissions   :', JSON.stringify(repo.json.permissions))
  const p = repo.json.permissions ?? {}
  console.log('  push allowed  :', p.push === true)
  if (p.push !== true) {
    console.log('  => CAUSE (b): the repo IS selected, but this token is READ-ONLY on it.')
    console.log('     Fix: edit the token and set Repository permissions -> Contents')
    console.log('     to "Read and write". (write implies read; no need to also set read.)')
  }
} else {
  console.log('  body:', JSON.stringify(repo.json).slice(0, 400))
}

console.log('\n=== does it see the repo in its own listing? ===')
const list = await api('/user/repos?per_page=100&affiliation=owner')
console.log('  status:', list.status)
if (list.status === 200) {
  const names = list.json.map(r => r.full_name)
  console.log('  owned repos visible to this token:', names.length ? names.join(', ') : '(none)')
  console.log('  workspace listed:', names.includes('sblzc/workspace'))
}

console.log('\n=== can it create a repo? (tells us whether it has account-level perms) ===')
const canCreate = await api('/user/repos', 'POST', {
  name: 'radio-permission-probe-tmp',
  private: true,
  description: 'temp probe, safe to delete',
})
console.log('  status:', canCreate.status, canCreate.status === 201 ? '(created - will try to delete)' : '')
if (canCreate.status === 201) {
  const del = await api('/repos/sblzc/radio-permission-probe-tmp', 'DELETE')
  console.log('  cleanup delete status:', del.status)
} else {
  console.log('  body:', JSON.stringify(canCreate.json).slice(0, 300))
}
