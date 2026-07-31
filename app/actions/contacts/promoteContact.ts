"use server";

import { headers } from "next/headers";
import { revalidatePath } from "next/cache";

import { createClient } from "@/lib/supabase/server";
import { audit } from "@/lib/audit";
import { loadAuthUser, resolveActiveOrg } from "@/lib/auth/server";
import { ROLE_RANK } from "@/lib/auth/types";

export type PromoteResult =
  | { ok: true }
  | { ok: false; error: string };

/**
 * Promove um contato de inbox (whatsapp) para contato CRM alterando a origem.
 * Requer role manager+ na organização.
 */
export async function promoteContactToCrm(
  contactId: string,
): Promise<PromoteResult> {
  const authUser = await loadAuthUser();
  if (!authUser) return { ok: false, error: "unauthenticated" };
  const activeOrg = await resolveActiveOrg(authUser);
  if (!activeOrg) return { ok: false, error: "forbidden" };
  if (ROLE_RANK[activeOrg.role] < ROLE_RANK.agent) {
    return { ok: false, error: "forbidden_role" };
  }

  const hdrs = await headers();
  const requestId = hdrs.get("x-request-id");

  const supabase = await createClient();

  // Verifica se o contato existe e pertence à org
  const { data: contact, error: selErr } = await supabase
    .from("contacts")
    .select("id, source, is_anonymized")
    .eq("id", contactId)
    .eq("organization_id", activeOrg.orgId)
    .maybeSingle();

  if (selErr) return { ok: false, error: selErr.message };
  if (!contact) return { ok: false, error: "not_found" };
  if (contact.is_anonymized) return { ok: false, error: "contato anonimizado (LGPD)" };

  // Se já é um contato CRM, não faz nada
  if (contact.source !== "whatsapp") return { ok: true };

  const { error: updErr } = await supabase
    .from("contacts")
    .update({
      source: "manual",
      source_metadata: {
        promoted_from: "whatsapp_inbox",
        promoted_at: new Date().toISOString(),
        promoted_by: authUser.id,
      },
    })
    .eq("id", contactId);

  if (updErr) return { ok: false, error: updErr.message };

  await audit({
    action: "contact.updated",
    actorUserId: authUser.id,
    organizationId: activeOrg.orgId,
    resourceType: "contact",
    resourceId: contactId,
    requestId,
    metadata: { promoted_from_inbox: true },
  });

  revalidatePath("/app/contacts");
  return { ok: true };
}
