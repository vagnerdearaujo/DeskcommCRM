-- 0095_contact_kind_inbox — Diferencia contatos CRM de contatos genéricos (inbox)
--
-- G9-07/08: contatos criados automaticamente via WhatsApp recebem kind='inbox'.
-- A lista de contatos do CRM mostra apenas kind='crm' por default.
-- Contatos 'inbox' podem ser promovidos a 'crm' via ação do usuário.
--
-- Idempotente: alter table add column if not exists + create or replace function.

-- Adiciona coluna kind com check constraint
alter table public.contacts
  add column if not exists kind text not null default 'crm'
  check (kind in ('crm', 'inbox'));

comment on column public.contacts.kind is
  'crm=contato gerenciado no CRM | inbox=contato genérico (ex: WhatsApp auto-criado). Só contatos crm aparecem na lista principal.';

-- Atualiza a função de upsert para marcar contatos WhatsApp como inbox
create or replace function public.fn_upsert_wa_contact(
  p_org uuid, p_kind text, p_phone text, p_lid text, p_chat_id text, p_notify text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  insert into public.contacts (organization_id, phone_number, source, kind, consent, tags, source_metadata, display_name)
  values (p_org, case when p_kind = 'phone' then p_phone end, 'whatsapp', 'inbox', '{}'::jsonb, '{}'::text[],
    case when p_kind = 'lid' then jsonb_build_object('waha_lid', p_lid, 'notify_name', nullif(p_notify, ''))
      else jsonb_build_object('waha_chat_id', p_chat_id, 'notify_name', nullif(p_notify, '')) end,
    nullif(p_notify, ''))
  on conflict (organization_id, wa_identity) where wa_identity is not null and is_merged_into is null
  do update set display_name = coalesce(contacts.display_name, excluded.display_name), updated_at = now()
  returning id into v_id;
  return v_id;
end; $$;
