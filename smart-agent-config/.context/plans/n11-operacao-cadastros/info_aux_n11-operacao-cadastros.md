# Documentação Auxiliar — N11 Operação e Cadastros

> Gerado em: 2026-08-09
> Plano canônico: `.context/plans/n11-operacao-cadastros.md`
> Plano completo: `.context/plans/n11-operacao-cadastros/plano_completo_n11-operacao-cadastros.md`
> Referências brutas nesta pasta: `ref_evolution_go.md`, `ref_email_transacional.md`

---

## ⚠️ Contrato da evolution-go — mesma ressalva da N9

A pesquisa devolveu endpoints da **Evolution API v2 (Node)**, que **não é** a que
o projeto usa. A fonte da verdade é
`server/crates/infrastructure_evolution/src/provider.rs`:

| Ação desta fase | **Path real do projeto** |
|---|---|
| QR de instância | `GET /instance/qr` (retorna **imagem base64**) |
| Estado da conexão (sonda) | `GET /instance/status` |
| Logout | `DELETE /instance/logout` |
| Reconectar | `POST /instance/reconnect` |
| Excluir | `DELETE /instance/delete/{uuid}` (**por UUID**, ver memória do projeto) |
| Webhook / assinatura de eventos | `POST /instance/{id}/advanced-settings` |
| Foto de perfil | `POST /user/avatar` |

Aproveitável do relatório (conceitual): a evolution-go/whatsmeow **tem keep-alive
de socket nativo** e reconexão automática com backoff; o recomendado de fora é
**sondar estado** (~30 s), não forçar reconexão — o que **corrige a premissa** de
copiar o keepalive de 60 s da v1. Teto prático de ~50 req/s por instância.

---

## E-mail transacional — comparativo e decisão

Relatório completo em `ref_email_transacional.md` (preços verificados em
agosto/2026, com fontes citadas).

| Provedor | Free tier | Primeiro pago | SDK Rust | Webhooks |
|---|---|---|---|---|
| **Brevo** | **300/dia permanente** | **$9/mês** | não (usar `reqwest`) | sim |
| Postmark | 100/mês | $15/mês | não (usar `reqwest`) | sim |
| Resend | 3.000/mês | — | `resend_rs` oficial | sim |
| SendGrid | 100/dia por 60 d | $19,95/mês | `sendgrid` | sim |
| Amazon SES | créditos AWS (free tier SES **descontinuado em jul/2026**) | $0,10/1k | `aws-sdk-sesv2` | via SNS |
| SMTP direto (`lettre`) | — | — | `lettre` 0.11.22 | não |

**Decisão registrada:** porta plugável `EmailSender` com **`BrevoSender` (HTTP
via `reqwest`) como default** — melhor free tier permanente, preço baixo no
primeiro degrau, sem SDK novo — e **`SmtpSender` (`lettre`) como alternativa**
para quem quiser servidor próprio. Mesmo padrão do pagamento, que já é porta.

### `lettre` — doc criada nesta rodada

`doc_dev/libs/rust/lettre.md` (✅ 2026-08-09, versão 0.11.22):
`AsyncSmtpTransport<Tokio1Executor>`, pool interno habilitado por padrão,
`MultiPart::alternative_plain_html`, `Credentials`, três modos de TLS (SMTPS 465,
STARTTLS 587, oportunista), `.timeout()` obrigatório em 0.11+, integração com
`secrecy`. Features: `["builder", "tokio1", "rustls", "pool"]`.

### Entregabilidade — o item de maior lead time da fase

Desde 2026, Google/Yahoo/Microsoft **exigem SPF + DKIM**:

- **SPF** — TXT no domínio raiz. Propaga em 15–30 min.
- **DKIM** — TXT em `<provedor>._domainkey.<dominio>`. **24–48 h** (às vezes 72).
  Um registro **por provedor**.
- **DMARC** — TXT em `_dmarc.<dominio>`, em fases: `p=none` (1–2 semanas de
  monitoramento) → `p=quarantine` → `p=reject`.

**Começar o DNS no dia 1 da fase.** A implementação não depende dele, mas a
entrega real sim.

---

## Libs (triagem 2a)

| Lib | Estado | Doc local | Uso |
|---|---|---|---|
| `reqwest` | USAR LOCAL | `rust/reqwest.md` (2026-05-31) | adaptador Brevo; cliente Evolution |
| `lettre` | **CRIADO nesta rodada** | `rust/lettre.md` (2026-08-09) | adaptador SMTP |
| `redis` | USAR LOCAL | `rust/redis.md` | token de recuperação (hash, TTL 1 h), rate limit |
| `argon2` | USAR LOCAL | `rust/argon2.md` | hash da nova senha |
| `secrecy` | USAR LOCAL | `rust/secrecy.md` | chave de API do provedor, token de recuperação |
| `sqlx` | USAR LOCAL | `rust/sqlx.md` | CRUD de whitelist, clientes, vínculo instância↔departamento |
| `go_router` | USAR LOCAL | `flutter/go_router.md` | rotas públicas novas |

---

## Fontes internas

| Item | Onde |
|---|---|
| Roteamento atual (o defeito da E2) | `data_postgres/src/adapters/atendimento.rs:346` (`buscar_primeiro_ativo`) |
| `AppInstance` (tabela sem uso) | migration `0005_operacional.sql` |
| Referência v1 do roteamento | `operacional/models.py:130` (`Departamento.validar_api_key`), `attendance_orchestrator.py:929` |
| Whitelist (repo sem gestão) | `infrastructure_postgres/src/integracoes/whitelist.rs` |
| Cliente PJ (repo completo sem consumidor) | `infrastructure_postgres/src/clientes/clientes.rs` |
| Polling de QR já resolvido | onboarding — commits `dba254b`, `e780e92`, `1503583` (inclui o bug do polling derrubando sessão recém-pareada) |
| Convite hoje | `invites_page.dart:337` — link **relativo** exibido para copiar |
| Rotação de refresh (revogar sessões) | `application` + `infrastructure_redis` (famílias de refresh já implementadas) |

---

## Grupo C — Observabilidade e Auditoria por etapa

| Etapa | Span/log | `audit_log` | Sanitização |
|---|---|---|---|
| E1 sonda | `whatsapp.sonda_estado` (verificadas, mudanças) — varredura sem mudança não loga em INFO | `whatsapp_instance.state_updated` com `origem="sonda"`; `.reconectada` | `api_key` em `SecretString`, nunca em log |
| E2 roteamento | campo `origem_fluxo` = `instancia`\|`fallback` | `whatsapp_instance.departamento_vinculado` (a resolução em si **não** audita — alto volume) | sem PII nova |
| E3 detalhe da conexão | span por ação | **todas**: `.bot_alterado`, `.renomeada`, `.webhook_alterado`, `.logout`, `.deletada` | **QR é credencial de pareamento** — nunca logar |
| E4 whitelist | span por ação | **todas**: `whitelist.adicionada`, `.alterada`, `.removida` | telefone **mascarado** na descrição |
| E5 contatos/PJ | span por ação | `contato.alterado`, `cliente.criado`/`.alterado`/`.desativado` — **campo** alterado, não valor | CNPJ/CPF, e-mail, endereço são PII |
| E6 perfil | log com telefone mascarado | **sem evento** (enriquecimento derivado) | — |
| E7 e-mail | `email.enviado` (tipo, provedor, status) | **`email.enviado`, `email.falhou`** com destino **mascarado** | chave de API em `SecretString`; **token nunca em log** |
| E8 senha/convite | span sem identificadores diretos | **`auth.redefinicao_solicitada`, `auth.senha_redefinida`, `convite.reenviado`** com `ip`/`user_agent` | token jamais em log/auditoria; resposta idêntica exista ou não o e-mail |
| E9 residuais | conforme item | `ReprocessarDeadLetter` já tem guard de escopo (N7) | — |

**Eventos novos propostos:** `whatsapp_instance.departamento_vinculado`,
`.bot_alterado`, `.renomeada`, `.webhook_alterado`, `.logout`, `.reconectada`;
`whitelist.adicionada`/`.alterada`/`.removida`; `cliente.criado`/`.alterado`/
`.desativado`; `contato.alterado`; `email.enviado`/`.falhou`;
`auth.redefinicao_solicitada`/`auth.senha_redefinida`; `convite.reenviado`.
