#!/usr/bin/env node
// =============================================================================
// Sensor "CI verde": sai 0 se o workflow CI passou no commit atual (HEAD).
//
//   node infra/ci-verde.mjs            # só consulta
//   node infra/ci-verde.mjs --esperar  # espera a execução em andamento terminar
//
// Não há ambiente local (Fase R4 do plano servidor-reestruturacao-dev-prod):
// fmt, clippy, testes com Postgres/Redis, Flutter e Python rodam na CI. O
// portão dos workflows de IA deixa de ser um script local e passa a ser o
// resultado da CI no commit que foi enviado. Multiplataforma (Windows/Linux):
// só depende de `git` e do `gh` autenticado.
// =============================================================================
import { execFileSync } from "node:child_process";

const esperar = process.argv.includes("--esperar");
const sh = (cmd, args) => execFileSync(cmd, args, { encoding: "utf8" }).trim();

const sha = sh("git", ["rev-parse", "HEAD"]);
const local = sh("git", ["status", "--porcelain"]);
if (local) {
  console.error("Há mudanças não commitadas: a CI só valida o que foi enviado (commit + push).");
}

const consulta = () =>
  JSON.parse(
    sh("gh", ["run", "list", "--workflow", "CI", "--commit", sha, "--limit", "1",
              "--json", "databaseId,status,conclusion,url"]) || "[]",
  )[0];

let run = consulta();
if (!run) {
  console.error(`Nenhuma execução da CI para ${sha.slice(0, 7)} — faça push do commit.`);
  process.exit(1);
}
if (run.status !== "completed" && esperar) {
  console.log(`CI em andamento (${run.url}); aguardando...`);
  try { sh("gh", ["run", "watch", String(run.databaseId), "--interval", "20"]); } catch { /* resultado abaixo */ }
  run = consulta();
}
if (run.status !== "completed") {
  console.error(`CI ainda em andamento para ${sha.slice(0, 7)}: ${run.url}`);
  process.exit(1);
}
if (run.conclusion !== "success") {
  console.error(`CI ${run.conclusion} para ${sha.slice(0, 7)}: ${run.url}`);
  process.exit(1);
}
console.log(`CI verde para ${sha.slice(0, 7)}: ${run.url}`);
