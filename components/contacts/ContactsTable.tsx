"use client";
import Link from "next/link";
import { useState } from "react";
import { formatRelative } from "date-fns";
import { ptBR } from "date-fns/locale";
import { toast } from "sonner";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import type { Contact } from "@/lib/types/contacts";
import { promoteContactToCrm } from "@/app/actions/contacts/promoteContact";

interface Props {
  contacts: Contact[];
}

function displayName(c: Contact): string {
  return c.display_name?.trim() || c.name?.trim() || "—";
}

function PromoteButton({ contactId }: { contactId: string }) {
  const [isPending, startTransition] = useState(false);
  const [done, setDone] = useState(false);

  if (done) return null;

  return (
    <form
      action={async () => {
        startTransition(true);
        const r = await promoteContactToCrm(contactId);
        if (r.ok) {
          setDone(true);
          toast.success("Contato promovido para o CRM.");
        } else {
          startTransition(false);
          toast.error(`Erro: ${r.error}`);
        }
      }}
    >
      <Button type="submit" size="sm" variant="outline" disabled={isPending}>
        {isPending ? "…" : "Promover"}
      </Button>
    </form>
  );
}

export function ContactsTable({ contacts }: Props) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Nome</TableHead>
          <TableHead>Email</TableHead>
          <TableHead>Telefone</TableHead>
          <TableHead>Tags</TableHead>
          <TableHead>Última atividade</TableHead>
          <TableHead>Status</TableHead>
          <TableHead></TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {contacts.map((c) => (
          <TableRow key={c.id} className="cursor-pointer">
            <TableCell className="font-medium">
              <Link href={`/app/contacts/${c.id}`} className="hover:underline">
                {displayName(c)}
              </Link>
            </TableCell>
            <TableCell className="text-muted-foreground">
              {c.email ?? "—"}
            </TableCell>
            <TableCell className="text-muted-foreground">
              {c.phone_number ?? "—"}
            </TableCell>
            <TableCell>
              <div className="flex flex-wrap gap-1">
                {c.tags.length === 0
                  ? <span className="text-muted-foreground text-xs">—</span>
                  : c.tags.map((t) => (
                      <Badge key={t} variant="neutral">{t}</Badge>
                    ))}
              </div>
            </TableCell>
            <TableCell className="text-muted-foreground text-sm">
              {c.last_activity_at
                ? formatRelative(new Date(c.last_activity_at), new Date(), { locale: ptBR })
                : "—"}
            </TableCell>
            <TableCell>
              <div className="flex flex-wrap gap-1">
                {c.is_anonymized && <Badge variant="destructive">Anonimizado</Badge>}
                {c.is_blocked && <Badge variant="warning">Bloqueado</Badge>}
                {c.source === "whatsapp" && <Badge variant="neutral">WhatsApp</Badge>}
                {!c.is_anonymized && !c.is_blocked && c.source !== "whatsapp" && (
                  <Badge variant="success">Ativo</Badge>
                )}
              </div>
            </TableCell>
            <TableCell>
              {c.source === "whatsapp" && <PromoteButton contactId={c.id} />}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
