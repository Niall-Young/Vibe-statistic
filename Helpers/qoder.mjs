import { query, qodercliAuth, accessToken } from '@qodercn-ai/qodercn-agent-sdk';
let release;
async function* noPrompt() { await new Promise(resolve => { release = resolve; }); }
let config = '';
for await (const chunk of process.stdin) config += chunk;
const input = JSON.parse(config || '{}');
const q = query({ prompt: noPrompt(), options: {
  auth: input.secret ? accessToken(input.secret) : qodercliAuth(),
  pathToQoderCLIExecutable: input.path,
  cwd: input.cwd, tools: [], mcpServers: {}, strictMcpConfig: true,
  settingSources: [], persistSession: false,
}});
try {
  await q.initializationResult();
  const usage = await q.getUsageInfo();
  console.log(JSON.stringify(usage));
} catch (_) { console.log(JSON.stringify({error: 'Qoder CN 查询失败，请检查登录和 CLI 版本'})); }
finally { release?.(); await q.close(); }
