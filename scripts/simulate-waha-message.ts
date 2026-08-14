/**
 * Simula UM inbound de texto pelo caminho de produção (webhook do WAHA) sem
 * depender de WhatsApp real — política 2026-08-05: o dev NUNCA conecta o
 * número real; a fila de mensagens do WhatsApp pertence ao prod (ver
 * docs/runbooks/waha-local.md §9).
 *
 * Diferença do `provoke-agent-turn.ts`: este valida SÓ o pipeline de ingestão
 * (contato/conversa/mensagem), sem exigir credencial LLM nem worker rodando.
 * O provoke exige os dois porque provoca o turno do agente.
 *
 * Uso (app dev no ar, sessão de teste registrada em channel_sessions):
 *   pnpm simulate:waha [--text "..."] [--session <waha_session_name>]
 *     [--from <ddd+numero>] [--app-url http://localhost:3003]
 */
import * as fs from "node:fs";
import * as path from "node:path";

import { createClient } from "@supabase/supabase-js";

const envFile = fs.readFileSync(path.join(process.cwd(), ".env.local"), "utf8");
const env: Record<string, string> = {};
for (const line of envFile.split("\n")) {
  const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
  if (m) env[m[1]!] = m[2]!.replace(/^"(.*)"$/, "$1");
}

const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL!, env.SUPABASE_SERVICE_ROLE_KEY!, {
  auth: { autoRefreshToken: false, persistSession: false },
});

function arg(name: string, fallback: string): string {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1]! : fallback;
}

const APP_URL = arg("app-url", env.NEXT_PUBLIC_APP_URL ?? "http://localhost:3003");
const SESSION_NAME = arg("session", "test-v2");
const TEXT = arg("text", "Mensagem simulada — pipeline de ingestão (dev sem número real)");
const FROM = arg("from", "5531999990001");

async function main(): Promise<void> {
  const { data: session, error } = await admin
    .from("channel_sessions")
    .select("id, organization_id, waha_session_name, webhook_path_token")
    .eq("waha_session_name", SESSION_NAME)
    .maybeSingle();
  if (error || !session) {
    throw new Error(
      `channel_session '${SESSION_NAME}' não encontrada no banco dev — registre uma sessão de teste em channel_sessions ou passe --session <nome>`,
    );
  }
  const s = session as {
    id: string;
    organization_id: string;
    waha_session_name: string;
    webhook_path_token: string;
  };

  const externalId = `false_${FROM}@c.us_SIM${Date.now()}`;
  const body = {
    event: "message",
    session: s.waha_session_name,
    payload: {
      id: externalId,
      from: `${FROM}@c.us`,
      to: "5531999990000@c.us",
      fromMe: false,
      body: TEXT,
      type: "chat",
      hasMedia: false,
      timestamp: Math.floor(Date.now() / 1000),
      _data: { notifyName: "Lead Simulado (dev)" },
    },
  };

  const url = `${APP_URL}/api/v1/webhooks/waha/${s.webhook_path_token}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  console.log(`[simulate] POST ${url} → ${res.status} ${text.slice(0, 200)}`);
  if (!res.ok) process.exit(1);

  // Prova que a ingestão gravou: mensagem com o external_id em `messages`.
  for (let i = 0; i < 20; i++) {
    const { data: msgs } = await admin
      .from("messages")
      .select("id, external_id, direction, channel_session_id")
      .eq("organization_id", s.organization_id)
      .eq("external_id", externalId)
      .limit(1);
    if (msgs && msgs.length > 0) {
      console.log(`[simulate] mensagem ingerida: ${JSON.stringify(msgs[0])}`);
      return;
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`mensagem ${externalId} não apareceu em messages após 10s`);
}

main().catch((err) => {
  console.error("[simulate] falhou:", err);
  process.exit(1);
});
