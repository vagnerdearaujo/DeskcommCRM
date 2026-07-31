"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";

import { createAdminClient } from "@/lib/supabase/admin";
import { audit } from "@/lib/audit";
import { loadAuthUser, resolveActiveOrg } from "@/lib/auth/server";
import { ROLE_RANK } from "@/lib/auth/types";
import { contactCreateSchema } from "@/lib/schemas/contacts";

export type CsvImportResult =
  | { ok: true; created: number; skipped: number; errors: string[] }
  | { ok: false; error: string };

interface CsvRow {
  name?: string;
  email?: string;
  phone_number?: string;
  cpf?: string;
  tags?: string;
  birthdate?: string;
}

function parseCsv(text: string): { headers: string[]; rows: string[][] } {
  const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
  if (lines.length < 2) return { headers: [], rows: [] };

  const headerLine = lines[0]!.trim();
  const headers = headerLine.split(",").map((h) => h.trim().toLowerCase());
  const rows = lines.slice(1).map((l) => l.split(",").map((c) => c.trim()));

  return { headers, rows };
}

function rowToObject(headers: string[], values: string[]): CsvRow {
  const obj: CsvRow = {};
  for (let i = 0; i < headers.length; i++) {
    const val = values[i];
    if (!val) continue;
    const key = headers[i]!;
    // Map CSV header aliases to schema field names
    switch (key) {
      case "name":
      case "display_name":
        obj.name = val;
        break;
      case "email":
      case "e-mail":
        obj.email = val;
        break;
      case "phone":
      case "phone_number":
      case "telefone":
      case "celular":
        obj.phone_number = val;
        break;
      case "cpf":
      case "documento":
      case "document":
        obj.cpf = val;
        break;
      case "tags":
      case "tag":
        obj.tags = val;
        break;
      case "birthdate":
      case "birth_date":
      case "data_nascimento":
      case "nascimento":
        obj.birthdate = val;
        break;
    }
  }
  return obj;
}

export async function importCsv(rawCsv: string): Promise<CsvImportResult> {
  const authUser = await loadAuthUser();
  if (!authUser) return { ok: false, error: "unauthenticated" };
  const activeOrg = await resolveActiveOrg(authUser);
  if (!activeOrg) return { ok: false, error: "forbidden" };
  if (ROLE_RANK[activeOrg.role] < ROLE_RANK.manager) {
    return { ok: false, error: "forbidden_role" };
  }

  const hdrs = await headers();
  const requestId = hdrs.get("x-request-id");

  const { headers: csvHeaders, rows } = parseCsv(rawCsv);
  if (csvHeaders.length === 0 || rows.length === 0) {
    return { ok: false, error: "CSV vazio ou formato inválido. Verifique se há cabeçalho + linhas." };
  }

  const admin = createAdminClient();
  let created = 0;
  let skipped = 0;
  const errors: string[] = [];

  for (let i = 0; i < rows.length; i++) {
    const raw = rowToObject(csvHeaders, rows[i]!);
    const payload: Record<string, unknown> = {
      source: "import",
      source_metadata: { imported_by: authUser.id, imported_at: new Date().toISOString() },
    };

    if (raw.name) payload.name = raw.name;
    if (raw.email) payload.email = raw.email;
    if (raw.phone_number) payload.phone_number = raw.phone_number;
    if (raw.cpf) payload.cpf = raw.cpf;
    if (raw.birthdate) payload.birthdate = raw.birthdate;
    if (raw.tags) {
      payload.tags = raw.tags.split(/[;,|]/).map((t) => t.trim()).filter(Boolean);
    }

    const parsed = contactCreateSchema.safeParse(payload);
    if (!parsed.success) {
      const issues = parsed.error.issues.map((iss) => iss.message).join("; ");
      errors.push(`Linha ${i + 2}: ${issues}`);
      skipped++;
      continue;
    }

    const { cpf, ...contactFields } = parsed.data;

    const insertPayload: Record<string, unknown> = {
      ...contactFields,
      organization_id: activeOrg.orgId,
    };

    // Store CPF hash for matching (decrypt/encrypt via edit flow, not bulk import)
    if (cpf) {
      const { createHash } = await import("node:crypto");
      insertPayload.cpf_hash = createHash("sha256").update(cpf.replace(/\D/g, "")).digest("hex");
    }

    const { error } = await admin.from("contacts").insert(insertPayload);
    if (error) {
      if (error.code === "23505") {
        skipped++;
        continue; // unique constraint — skip silently
      }
      errors.push(`Linha ${i + 2}: ${error.message}`);
      skipped++;
      continue;
    }
    created++;
  }

  await audit({
    action: "contact.created",
    actorUserId: authUser.id,
    organizationId: activeOrg.orgId,
    resourceType: "contact",
    requestId,
    metadata: {
      bulk_import: true,
      total: rows.length,
      created,
      skipped,
      errors_count: errors.length,
    },
  });

  revalidatePath("/app/contacts");
  return { ok: true, created, skipped, errors };
}
