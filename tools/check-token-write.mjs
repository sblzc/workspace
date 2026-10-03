// Answer ONE question: does the token in D:/radio/.github-token have WRITE access
// to sblzc/workspace?
//
// Why this exists: GET /repos/{owner}/{repo} reports
//   permissions: { "push": true, ... }
// even for a token that every write rejects with 403
// ("Resource not accessible by personal access token"). So `permissions.push`
// is NOT a usable signal for fine-grained tokens -- you have to attempt a write.
//
// This script performs a real write (creates a throwaway branch ref, then
// deletes it). It never prints the token. ASCII only.
//
//   node tools/check-token-write.mjs
//
// Exit code 0 = write access OK. Exit code 1 = read-only / not granted.
import { readFileSync } from 'node:fs'

const REPO = 'sblzc/workspace'
const TOKEN_FILE = 'D:/radio/.github-token'

let token
try {
  token = readFileSync(TOKEN_FILE, 'utf8').trim()
} catch {
  console.error(`FAIL  cannot read ${TOKEN_FILE}`)
  process.exit(1)
}
if (!/^(github_pat_|ghp_)/.test(token)) {
  console.error('FAIL  that file does not look like a GitHub token')
  process.exit(1)
}

const API = `https://api.github.com/repos/${REPO}`
const H = {
  Authorization: `Bearer ${token}`,
  Accept: 'application/vnd.github+json',
  'X-GitHub-Api-Version': '2022-11-28',
  'User-Agent': 'dsh-check-token-write',
  'Content-Type': 'application/json',
}
const call = (path, method, body) =>
  fetch(`${API}${path}`, { method, headers: H, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30000) })

console.log(`checking write access to ${REPO}`)
console.log(`  token: ${token.slice(0, 22)}...  (${token.length} chars, from ${TOKEN_FILE})\n`)

const me = await fetch('https://api.github.com/user', { headers: H, signal: AbortSignal.timeout(30000) }).catch(() => null)
if (me?.status === 200) {
  const u = await me.json()
  console.log(`  identity : ${u.login} (id ${u.id})`)
} else {
  console.log(`  identity : FAILED (status ${me?.status}) -- token is invalid, expired, or revoked`)
  process.exit(1)
}

const repo = await call('', 'GET')
if (repo.status === 404) {
  console.log(`  repo     : NOT VISIBLE -- add "${REPO}" to this token's Selected repositories.`)
  process.exit(1)
}
console.log(`  repo     : ${(await repo.json()).full_name}  (default branch: main)\n`)

// The one probe that matters: a real write.
const branch = 'write-access-check-tmp'
const head = await call('/git/ref/heads/main', 'GET')
if (head.status !== 200) {
  console.log(`FAIL  cannot read refs/heads/main (status ${head.status})`)
  process.exit(1)
}
const sha = (await head.json()).object.sha

const created = await call('/git/refs', 'POST', { ref: `refs/heads/${branch}`, sha })
if (created.status === 201) {
  const del = await call(`/git/refs/heads/${branch}`, 'DELETE')
  console.log(`  write    : OK (created and deleted refs/heads/${branch}; delete status ${del.status})`)
  console.log('\nPASS  this token can push. If `git push` still 403s, the problem is elsewhere.')
  process.exit(0)
}

const body = await created.json().catch(() => ({}))
console.log(`  write    : DENIED (status ${created.status})`)
console.log(`             ${body.message ?? ''}`)
console.log('\nFAIL  this token is READ-ONLY on this repository.')
console.log('      Fix it at https://github.com/settings/personal-access-tokens')
console.log('        - Repository access      -> include  ' + REPO)
console.log('        - Repository permissions -> Contents = Read and write')
console.log('      "write" implies "read", so do not set Contents twice.')
console.log('      Then: Set-Content -Path D:\\radio\\.github-token -Value \'<NEW_TOKEN>\' -NoNewline -Encoding ascii')
console.log('      Then: node D:\\radio\\tools\\check-token-write.mjs   (expect PASS)')
process.exit(1)
