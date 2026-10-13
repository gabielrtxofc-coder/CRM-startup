import { describe, expect, it } from "vitest";

import { env } from "@/lib/env";
import { assertUrlDeMidiaSegura } from "@/lib/messaging/media/url-de-midia-externa";

/**
 * Origem PRIVADA que nunca é a origem desta instalação.
 *
 * O caso "Storage de outra origem" existe para provar que PARECER Storage não
 * herda a exceção — e para isso a URL tem de ser de outra origem. A versão
 * anterior fixava `http://127.0.0.1:54321`, que é justamente o endereço do
 * Supabase local que o próprio projeto documenta e usa:
 *
 *   - `docs/specs/08-spec-deploy-observability.md` — `NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321`
 *   - `infra/executor-proprio/README.md` — "o e2e sobe o Supabase em portas fixas (54321/54322)"
 *   - `docs/handoffs/HANDOFF-indice-de-atrito.md` — manda pôr o `.env.local` em `127.0.0.1:54321`
 *
 * `tests/setup/vitest.setup.ts` carrega `.env`/`.env.local` do disco e o valor
 * real VENCE o placeholder. Consequência medida em 2026-10-13 (importação deste
 * projeto para o repositório da startup, sandbox com o `.env.local` do setup
 * local): `pnpm test:unit` → 22941✓/1✗, e o ✗ era este caso — a guarda ACEITOU
 * a URL porque ela É a origem assinada da instalação, exatamente como o contrato
 * dela manda. Vermelho falso num teste de segurança é o pior tipo: ensina a
 * ignorar o gate e faz parecer quebrada a única exceção que a anti-SSRF tem.
 *
 * No CI nada disso aparece: sem `.env`, vale `https://test-placeholder.invalid`,
 * e 54321 volta a ser "outra origem".
 *
 * Continua sendo host PRIVADO de propósito — o motivo esperado é
 * `unsafe_url:private_host`, decidido por `assertSafeOutboundUrl` antes de
 * qualquer resolução de DNS, então o caso não depende de rede.
 */
function origemPrivadaEstrangeira(): string {
  let origemDaInstalacao: string | null = null;
  try {
    origemDaInstalacao = new URL(env.NEXT_PUBLIC_SUPABASE_URL).origin;
  } catch {
    // URL inválida: qualquer origem privada serve de "estrangeira".
  }
  for (const porta of [54321, 54322, 54323]) {
    const candidata = `http://127.0.0.1:${porta}`;
    if (candidata !== origemDaInstalacao) return candidata;
  }
  return "http://127.0.0.1:1";
}

describe("assertUrlDeMidiaSegura", () => {
  it("aceita a URL assinada pelo Storage desta instalação, sem consultar DNS", async () => {
    await expect(
      assertUrlDeMidiaSegura(`${env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/sign/propostas/o/p.pdf?token=t`),
    ).resolves.toBeUndefined();
  });

  it("a origem do caso 'outra origem' nunca é a desta instalação", () => {
    // Trava do fixture acima: sem ela, quem re-fixar um endereço que coincide
    // com o `.env` de quem roda volta a ter verde no caso errado — a guarda
    // aceita por ser a origem DA INSTALAÇÃO, e o teste deixa de medir a exceção.
    expect(origemPrivadaEstrangeira()).not.toBe(new URL(env.NEXT_PUBLIC_SUPABASE_URL).origin);
  });

  it.each([
    ["metadata da nuvem", "http://169.254.169.254/latest/meta-data/", "unsafe_url:private_host"],
    ["IP privado do compose", "http://10.0.0.7:8080/x", "unsafe_url:private_host"],
    ["CGNAT (só a guarda por IP pega)", "https://100.64.0.1/x", "unsafe_url:private_ip"],
    ["esquema que não é http", "file:///etc/passwd", "unsafe_url:scheme"],
    ["lixo", "não é url", "unsafe_url:invalid"],
    // Parece Storage, mas não é a origem DESTA instalação: não herda a exceção.
    [
      "Storage de outra origem",
      `${origemPrivadaEstrangeira()}/storage/v1/object/sign/x?token=t`,
      "unsafe_url:private_host",
    ],
  ])("recusa %s", async (_nome, url, motivo) => {
    await expect(assertUrlDeMidiaSegura(url)).rejects.toThrow(motivo);
  });
});
