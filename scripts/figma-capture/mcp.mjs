// Minimal client for the figma-console MCP server (Desktop Bridge plugin).
// The endpoint comes from FIGMA_MCP_URL / FIGMA_MCP_TOKEN, or from the
// "figma-console-shared" server in ~/.claude.json.
import fs from 'node:fs';
import os from 'node:os';

function config() {
  if (process.env.FIGMA_MCP_URL) {
    const token = process.env.FIGMA_MCP_TOKEN;
    return { url: process.env.FIGMA_MCP_URL, headers: token ? { Authorization: `Bearer ${token}` } : {} };
  }
  const claude = JSON.parse(fs.readFileSync(`${os.homedir()}/.claude.json`, 'utf8'));
  const server = claude.mcpServers?.['figma-console-shared'];
  if (!server) throw new Error('Set FIGMA_MCP_URL or configure figma-console-shared in ~/.claude.json');
  return server;
}
const cfg = config();
const H = { ...cfg.headers, 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' };
async function rpc(body, sid) {
  const r = await fetch(cfg.url, { method: 'POST', headers: sid ? { ...H, 'Mcp-Session-Id': sid } : H, body: JSON.stringify(body) });
  const text = await r.text();
  const m = text.match(/^data: (.*)$/m);
  return { sid: r.headers.get('mcp-session-id'), json: m ? JSON.parse(m[1]) : (text ? JSON.parse(text) : null) };
}
/** Calls an MCP tool, retrying a few times when the connection drops mid-call. */
export async function call(name, args) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await callOnce(name, args);
    } catch (e) {
      if (attempt >= 3 || e?.cause?.code !== 'UND_ERR_SOCKET') throw e;
      await new Promise((r) => setTimeout(r, 2000 * attempt));
    }
  }
}

async function callOnce(name, args) {
  const init = await rpc({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'capture', version: '1' } } });
  const sid = init.sid;
  try {
    await rpc({ jsonrpc: '2.0', method: 'notifications/initialized' }, sid);
    const res = await rpc({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name, arguments: args } }, sid);
    return res.json;
  } finally {
    await fetch(cfg.url, { method: 'DELETE', headers: { ...H, 'Mcp-Session-Id': sid } }).catch(() => {});
  }
}

/** Runs [code] in the Figma plugin and returns its result, throwing on failure. */
export async function execute(code, timeout = 180000) {
  const res = await call('figma_execute', { code, timeout });
  const text = res?.result?.content?.[0]?.text ?? JSON.stringify(res);
  const parsed = JSON.parse(text);
  if (!parsed.success) throw new Error(text.slice(0, 600));
  return parsed.result;
}
