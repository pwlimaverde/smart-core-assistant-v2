# Documentação Auxiliar — Regras do bot e permissões

> Gerado em: 2026-09-06
> Plano canônico: `.context/plans/regras-do-bot-e-permissoes.md`
> Plano completo: `.context/plans/regras-do-bot-e-permissoes/plano_completo_regras-do-bot-e-permissoes.md`

---

## 1. Este plano quase não tem dependência externa

As sete entregas são **regras de negócio e autorização** sobre estrutura que já
existe. Nenhuma chama serviço de terceiro, nenhuma precisa de lib nova.

Isso é consequência de como o plano foi delimitado: tudo que dependia de
integração externa (mídia no WhatsApp, e-mail transacional, R2, `Analyse`) já
está em N9, N10 ou N11, **com pesquisa própria já coletada**:

| Frente | Onde está a pesquisa |
|---|---|
| evolution-go | `.context/plans/n9-conversa-completa/ref_evolution_go.md` (1067 linhas) |
| Cloudflare R2 | `.context/plans/n9-conversa-completa/ref_cloudflare_r2.md` (1138 linhas) |
| E-mail transacional | `.context/plans/n11-operacao-cadastros/ref_email_transacional.md` (1021 linhas) |

**Consultar esses arquivos antes de pesquisar qualquer coisa nessas frentes.**

---

## 2. Libs — triagem da central local (`doc_dev/libs/`)

Todas **USAR LOCAL**. Nenhuma exigiu Context7 ou pesquisa externa.

| Lib | Stack | Versão | Verificada | Uso neste plano |
|---|---|---|---|---|
| `sqlx` | rust | 0.9 (workspace) | 2026-06-10 | D1 (gravar confiança), D2 (rodízio com `UPDATE...RETURNING`), D5 |
| `jsonwebtoken` | rust | — | — | D4 — escopos no JWT |
| `tonic` / `tonic-web` | rust | 0.14.6 / 0.14.1 | 2026-06-04 | D3, D7 (RPCs novos) |
| `redis` | rust | 0.25.0 | — | D5 (lock do scheduler), D6 (pub/sub) |
| `tracing` | rust | 0.1.40 | — | transversal |

### Versões fixadas (`server/Cargo.toml`)

```
sqlx 0.9 · serde 1.0 · tokio 1.38 · tracing 0.1.40 · secrecy 0.10.3
argon2 0.5 · redis 0.25.0 · tonic 0.14.6 · tonic-web 0.14.1 · aws-sdk-s3 1.x
```

### Divergência de versão registrada (não afeta este plano)

| Crate | Publicada | No `Cargo.lock` |
|---|---|---|
| `reqwest` | 0.13.4 (2026-05-25, confirmado em crates.io) | **0.12.28** |
| `aws-sdk-s3` | 1.145.0 | 1.135.0 |

→ O salto `reqwest` 0.12 → 0.13 é de major e não foi feito. **Código novo deve
seguir a API 0.12.x.** Higiene de dependência, plano próprio.

---

## 3. Contratos internos — o material que importa

### 3.1 D4 — origem dos escopos do JWT

`application/src/auth/login.rs:244` (`derivar_escopos`), gêmeo em
`refresh.rs:133`:

```
1. is_superuser                    → ["*"]
2. module_permissions como array   → a própria lista de escopos
3. module_permissions como objeto  → chaves com valor true
4. FALLBACK pelo role              → admin|owner: [atendimentos:read,
                                      atendimentos:write, clientes:write,
                                      tenant:admin]
                                     demais:      [atendimentos:read,
                                      atendimentos:write, clientes:write]
```

Exigidos de verdade no `data_postgres`:
`ctx.exigir_qualquer(&["atendimentos:write", "tenant:admin"])`.

**Referência da v1** (`tenants/permissions.py`): 8 módulos com
`view`/`edit`/`delete` (`painel_admin`, `clientes`, `operacional`,
`treinamento`, `atendimentos`, `atendimento`, `configuracoes`, `usuarios`) e
4 papéis (`admin`, `manager`, `staff`, `viewer`). `has_module_permission`
autorizava o tenant-admin inteiro (`tenants/admin_client.py`).

**Telas atuais** (`tenant_users_page.dart`, `invites_page.dart`): dropdown com só
`admin` e `staff`; escopo cru em `CheckboxListTile`; fluxos por ID digitado.

### 3.2 D1 — onde a confiança se perde

| Ponto | Arquivo | Fato |
|---|---|---|
| Retorno da IA | `worker/main.rs:543` | `responder_via_ia` devolve **só** `resposta_texto` |
| Palavra `confiabilidade` | `worker/main.rs` | **zero ocorrências** |
| Único `UPDATE` | `mensagens.rs:348-357` | `registrar_resposta_bot` |
| Quem o chama | `tests/atendimentos/mod.rs:161` | **só o teste** |
| Transbordo hoje | `worker/main.rs:222` | `aplicar_transferencia_ia` (N6.3), decidido pelo LLM |

Config do tenant já tem `similarity_threshold` e `vector_distance_threshold` —
os novos limiares vão ao lado.

### 3.3 D2 — rodízio

`oraculo_atendente`: `disponivel`, `max_atendimentos_simultaneos`,
`data_ultima_atribuicao`. Repositório: `atualizar_ultima_atribuicao`.
Atribuição hoje: só `assumir_atendimento` (`atendimento.rs:905`), por arraste.

**Padrão de concorrência a reusar:** `vouchers.rs:159` —
`UPDATE ... WHERE <condição de limite> RETURNING`, que já resolve corrida entre
requisições no resgate de voucher.

### 3.4 D3 — o interruptor de mão única

| Fato | Onde |
|---|---|
| Assumir desliga o bot | `atendimentos.rs:461` (`bot_pode_atender = false`) |
| Desatribuir **não** religa, de propósito | `atendimentos.rs:148` (doc do trait) |
| Nenhum `UPDATE` devolve `true` | busca em todo o `server/` |
| Barreira do bot no worker | `worker/main.rs:1318` |
| `bot_pode_atender` no Flutter | **zero arquivos** |

A v1 tinha `AppInstance.resposta_bot` + rota `instances/<pk>/toggle-bot/`.

### 3.5 D5 — o scheduler

Cinco rotinas hoje: `processar_feedback_vencido`, `processar_midia_expirada`,
`processar_vetorizacao_pendente`, `processar_intents_sem_embedding`,
`reconciliar_conexoes_whatsapp`. Padrão: lote por variável de ambiente, lock com
TTL, `chamar_rpc` para o `data_postgres`.

🚩 **Armadilha de nome:** `feedback_timeout` e `feedback_expirado_em` são da
**pesquisa de satisfação**, não do abandono da conversa. E
`solicitar_pesquisa_satisfacao` (`atendimento.rs:85`) dispara **na transição de
status** — encerrar por inatividade não pode acionar a pesquisa.

### 3.6 D6 — o realtime não tem destinatário

- Canal: `tenant:{id}:events` (`worker/main.rs:896`, `realtime.rs:60`) — **um
  para a empresa toda**;
- `AtendimentoEvent` (`admin.proto:1289`): `event_type`, `tenant_id`, `payload`.
  **Sem destinatário**;
- tipos publicados: `whatsapp.conexao`, `whatsapp.presenca`, `kanban.movido`,
  `mensagem.recebida`, `mensagem.enviada`, `mensagem.status_atualizado`.
  **Nenhum de atribuição.**

**Dependência externa ao plano:** o realtime do desktop é entrega da **N9**. Sem
ela, a notificação não chega ao app instalado.

### 3.7 D7 — o que falta no superusuário

`tenants_paymentrecord` existe e está **vazia**; a v1 tinha
`bo/tenant/<uuid>/register-payment/`. E a v1 registrava `User` no Django admin —
a v2 não tem gestão global de usuários.

---

## 4. Observabilidade e auditoria (Grupo C)

### Vocabulário já em uso — reusar antes de criar sinônimo

`atendimento.aberto` · `atendimento.feedback_expirado` ·
`atendimento.transferido_por_ia` · `bot.degradado` · **`bot.respondeu`** ·
**`bot.silenciado`** · `kanban.movido` · `mensagem.confirmada` ·
`mensagem.enviada` · `mensagem.envio_falhou` · `mensagem.falha_persistencia` ·
`mensagem.persistida` · `midia.analisada` · `midia.purgada` ·
`ticket.transicionado` · `webhook.received/duplicated/ignored/rejected`

> **`bot.silenciado` já existe** e já é emitido pela barreira
> (`worker/main.rs:1246` e `:1818`). A **D3 deve reusá-lo**, acrescentando o
> motivo (`instancia` / `conversa` / `humano_ativo`).

### Resumo por entrega

| Entrega | Log/trace novo | `audit_log` | Sensível? |
|---|---|---|---|
| **D4** | `origem_escopos` no span de login | 🔒 **obrigatório**: `permissao.alterada` com antes/depois | escopos não são segredo |
| **D1** | `confianca` e `decisao` no span | reusar `bot.respondeu` | pergunta e resposta **não** vão para log |
| **D2** | `atendente_id` e `motivo` | **novo** `atendimento.atribuido_automaticamente` | só ids |
| **D3** | reusar `bot.silenciado` + motivo | **novos** `instancia.bot_alterado`, `atendimento.bot_alterado` | sem segredo |
| **D5** | total do lote, não um por atendimento | **novo** `atendimento.encerrado_por_inatividade` | — |
| **D6** | `atendente_id` na publicação | sem evento (*ausência intencional*) | payload sem conteúdo de mensagem |
| **D7** | — | 🔒 **obrigatório**: `pagamento.registrado_manualmente`, `usuario.alterado_pelo_superusuario` | — |

🔒 = evento crítico pelo `08_diretrizes_seguranca.md` §4.2 (`TenantUser`,
permissões, `PaymentRecord`).

### Regras herdadas da arquitetura — não reabrir

- `error_core` é a base de todos os erros; `infrastructure_*` **não** depende de
  `observability` (evita ciclo).
- `#[tracing::instrument(err)]` só onde **todo** erro é falha real de infra.
- Repositórios de tenant: `run_in_tenant_transaction` + `#[instrument(skip_all)]`.
- Auditoria vai **assíncrona** pelo `transport::bus` → `data_postgres`.
- Metadados mínimos: timestamp UTC, `user_id` do `RequestContext`,
  `ip_address`, `user_agent`, `event_type`, descrição **sem** o segredo.
- `mascarar_telefone` já existe no worker — usar em todo log que toque telefone.
