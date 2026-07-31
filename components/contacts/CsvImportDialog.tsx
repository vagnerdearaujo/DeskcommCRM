"use client";
import { useState, useTransition } from "react";
import { toast } from "sonner";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { importCsv, type CsvImportResult } from "@/app/actions/contacts/importCsv";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
}

export function CsvImportDialog({ open, onOpenChange }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [result, setResult] = useState<CsvImportResult | null>(null);
  const [isPending, startTransition] = useTransition();

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0] ?? null;
    setFile(f);
    setResult(null);
  }

  function handleImport() {
    if (!file) return;
    setResult(null);
    startTransition(async () => {
      const text = await file.text();
      const r = await importCsv(text);
      setResult(r);
      if (r.ok) {
        toast.success(`${r.created} contatos importados.`);
      } else {
        toast.error(`Erro: ${r.error}`);
      }
    });
  }

  function handleClose() {
    setFile(null);
    setResult(null);
    onOpenChange(false);
  }

  const hasResult = result !== null && result.ok;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Importar contatos (CSV)</DialogTitle>
          <DialogDescription>
            Faça upload de um arquivo CSV com os contatos. O cabeçalho deve conter
            pelo menos um dos campos: <strong>name</strong>, <strong>email</strong>,{" "}
            <strong>phone</strong>, <strong>cpf</strong>, <strong>tags</strong>,{" "}
            <strong>birthdate</strong>.
          </DialogDescription>
        </DialogHeader>

        {!hasResult ? (
          <div className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="csv-file">Arquivo CSV</Label>
              <input
                id="csv-file"
                type="file"
                accept=".csv,.txt"
                onChange={handleFileChange}
                className="block w-full text-sm text-muted-foreground file:mr-4 file:rounded file:border-0 file:bg-primary/10 file:px-4 file:py-2 file:text-sm file:font-semibold file:text-primary hover:file:bg-primary/20"
              />
            </div>

            {result && !result.ok && (
              <div className="rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                {result.error}
              </div>
            )}

            <DialogFooter>
              <Button type="button" variant="ghost" onClick={handleClose} disabled={isPending}>
                Cancelar
              </Button>
              <Button type="button" onClick={handleImport} disabled={!file || isPending}>
                {isPending ? "Importando…" : "Importar"}
              </Button>
            </DialogFooter>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="rounded-md border border-green-300 bg-green-50 px-3 py-3 text-sm text-green-800">
              <p className="font-medium">Importação concluída</p>
              <ul className="mt-1 list-inside list-disc space-y-0.5">
                <li>Criados: <strong>{result.ok && result.created}</strong></li>
                <li>Pulados: <strong>{result.ok && result.skipped}</strong></li>
                {result.ok && result.errors.length > 0 && (
                  <li>Erros: <strong>{result.errors.length}</strong></li>
                )}
              </ul>
            </div>

            {result.ok && result.errors.length > 0 && (
              <details className="text-xs text-muted-foreground">
                <summary className="cursor-pointer font-medium">
                  Ver detalhes dos erros ({result.errors.length})
                </summary>
                <ul className="mt-1 max-h-40 space-y-0.5 overflow-y-auto">
                  {result.errors.map((err, i) => (
                    <li key={i} className="text-destructive">{err}</li>
                  ))}
                </ul>
              </details>
            )}

            <DialogFooter>
              <Button type="button" onClick={handleClose}>
                Fechar
              </Button>
            </DialogFooter>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
