import nodemailer from "nodemailer";

interface SendArgs {
  to: string | string[];
  subject: string;
  html: string;
  text?: string;
  replyTo?: string;
  tags?: { name: string; value: string }[];
}

interface SendResult {
  ok: boolean;
  id?: string;
  error?: "not_configured" | "send_failed" | "rate_limited";
  details?: string;
}

interface BrevoConfig {
  host: string;
  port: number;
  auth: {
    user: string;
    pass: string;
  };
}

/**
 * Brevo SMTP wrapper.
 *
 * Usa a infraestrutura SMTP já existente no VPS (host: smtp-relay.brevo.com:587,
 * STARTTLS) que também alimenta o GoTrue self-hosted. Credenciais são lidas
 * das variáveis de ambiente BREVO_SMTP_USER / BREVO_SMTP_PASS (mismo padrão do
 * GoTrue, reutilizando a conta Brevo já validada para vagnercoachsite e
 * GoTrue).
 *
 * Comportamento defensivo: quando as credenciais não estão configuradas, faz log
 * do payload no console em DEV (nunca em prod) e retorna { ok: false, error: 'not_configured' }
 * — o caller decide se isso é fatal ou não.
 */
const BREVO_HOST = process.env.BREVO_SMTP_HOST || "smtp-relay.brevo.com";
const BREVO_PORT = Number(process.env.BREVO_SMTP_PORT) || 587;
const BREVO_USER = process.env.BREVO_SMTP_USER || "";
const BREVO_PASS = process.env.BREVO_SMTP_PASS || "";

function getTransporter(): nodemailer.Transporter {
  if (BREVO_HOST && BREVO_PORT && BREVO_USER && BREVO_PASS) {
    return nodemailer.createTransport({
      host: BREVO_HOST,
      port: BREVO_PORT,
      secure: BREVO_PORT === 465, // false para 587 (STARTTLS)
      auth: {
        user: BREVO_USER,
        pass: BREVO_PASS,
      },
      tls: {
        // não falhar em certificados auto-assinados em dev
        rejectUnauthorized: process.env.NODE_ENV === "production",
      },
    });
  }
  return null as any;
}

function fromAddress(): string {
  return process.env.RESEND_FROM_EMAIL || "DeskcommCRM <crm@vagnercoach.com.br>";
}

export async function sendEmail(args: SendArgs): Promise<SendResult> {
  const transporter = getTransporter();

  if (!transporter) {
    if (process.env.NODE_ENV !== "production") {
      console.warn(
        "[email] BREVO SMTP não configurado — email não enviado. Payload:",
        {
          to: args.to,
          subject: args.subject,
          preview: args.text?.slice(0, 200) ?? args.html.slice(0, 200),
        },
      );
      return { ok: false, error: "not_configured" };
    }
    return { ok: false, error: "not_configured" };
  }

  try {
    const info = await transporter.sendMail({
      from: fromAddress(),
      to: Array.isArray(args.to) ? args.to.join(", ") : args.to,
      subject: args.subject,
      text: args.text,
      html: args.html,
      replyTo: args.replyTo,
    });

    return { ok: true, id: info.messageId };
  } catch (err) {
    const isRateLimit = String(err).toLowerCase().includes("rate") || String(err).toLowerCase().includes("limit");
    return {
      ok: false,
      error: isRateLimit ? "rate_limited" : "send_failed",
      details: err instanceof Error ? err.message : String(err),
    };
  }
}

export function isEmailConfigured(): boolean {
  const t = getTransporter();
  return t !== null;
}