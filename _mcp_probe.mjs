// Probe the hosted GitHub MCP endpoint with the real PAT.
// Answers the one question that gates the whole connector: does
// api.githubcopilot.com/mcp accept a fine-grained PAT and list tools?
//
// ASCII only. Run: node _mcp_probe.mjs
import { readFileSync } from 'node:fs'

const ENDPOINT = 'https://api.githubcopilot.com/mcp'
const token = readFileSync('D:/radio/.github-token', 'utf8').trim()
if (!token) throw new Error('no token')

const HEADERS = {
  'Content-Type': 'application/json',
  Accept: 'application/json, text/event-stream',
  Authorization: `Bearer ${token}`,
}

async function rpc(id, method, params) {
  const res = await fetch(ENDPOINT, {
    method: 'POST',
    headers: HEADERS,
    body: JSON.stringify({ jsonrpc: '2.0', id, method, params }),
    signal: AbortSignal.timeout(30000),
  })
  const text = await res.text()
  let sessionId = res.headers.get('mcp-session-id')
  return { status: res.status, sessionId, text, ct: res.headers.get('content-type') }
}

// Streamable HTTP may answer as SSE; pull the JSON payload out.
function parseBody(text, ct) {
  if (ct && ct.includes('text/event-stream')) {
    const out = []
    for (const line of text.split('\n')) {
      if (line.startsWith('data:')) out.push(line.slice(5).trim())
    }
    return out.map(s => { try { return JSON.parse(s) } catch { return s } })
  }
  try { return [JSON.parse(text)] } catch { return [text] }
}

console.log('=== 1. initialize ===')
const init = await rpc(1, 'initialize', {
  protocolVersion: '2025-06-18',
  capabilities: {},
  clientInfo: { name: 'dsh-probe', version: '1.0.0' },
})
console.log('  status     :', init.status)
console.log('  content-ct :', init.ct)
console.log('  session-id :', init.sessionId)
const initBody = parseBody(init.text, init.ct)
console.log('  server     :', JSON.stringify(initBody[0]?.result?.serverInfo ?? initBody[0]))
console.log('  protocol   :', initBody[0]?.result?.protocolVersion)
if (init.status !== 200) {
  console.log('  RAW:', init.text.slice(0, 600))
  process.exit(1)
}

// Streamable HTTP wants the session echoed back on later calls.
const session = init.sessionId
const H2 = session ? { ...HEADERS, 'mcp-session-id': session } : HEADERS

console.log('\n=== 2. notifications/initialized ===')
const ready = await fetch(ENDPOINT, {
  method: 'POST',
  headers: H2,
  body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
  signal: AbortSignal.timeout(30000),
})
console.log('  status:', ready.status)

console.log('\n=== 3. tools/list ===')
const tl = await fetch(ENDPOINT, {
  method: 'POST',
  headers: H2,
  body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list', params: {} }),
  signal: AbortSignal.timeout(30000),
})
const tlText = await tl.text()
console.log('  status:', tl.status)
const tlBody = parseBody(tlText, tl.headers.get('content-type'))
const tools = tlBody[0]?.result?.tools ?? []
console.log('  tool count:', tools.length)
console.log('  tools:', tools.map(t => t.name).join(', ').slice(0, 2000))
if (!tools.length) console.log('  RAW:', tlText.slice(0, 800))
