import Link from "next/link";

import { SignupForm } from "@/components/auth/SignupForm";
import { branding } from "@/lib/branding";

export const metadata = { title: "Criar conta" };

interface PageProps {
  searchParams: Promise<{ invite?: string; email?: string }>;
}

export default async function SignupPage({ searchParams }: PageProps) {
  const params = await searchParams;

  return (
    <div className="space-y-6">
      <div className="space-y-1.5 text-center">
        <h1 className="text-2xl font-semibold tracking-tight">Criar conta</h1>
        <p className="text-sm text-muted-foreground">
          {params.invite
            ? "Você foi convidado para usar o CRM"
            : `Comece a usar o ${branding().name} por meio de um convite`}
        </p>
      </div>
      <SignupForm
        email={params.email ?? undefined}
        inviteToken={params.invite ?? undefined}
      />
      <p className="text-center text-sm text-muted-foreground">
        Já tem conta?{" "}
        <Link href="/login" className="font-medium text-foreground underline underline-offset-4">
          Entrar
        </Link>
      </p>
    </div>
  );
}
