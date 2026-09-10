# 32 — Cobertura de N9–N12 e o delta real do levantamento

> **Correção de rota.** Os docs 29, 30 e 31 levantaram lacunas como se o
> planejamento estivesse por fazer. **Não estava.** Existem quatro planos
> estruturados de **2026-08-09** — N9, N10, N11 e N12 — derivados do doc 26
> (2026-08-08), todos com `status: filled` e `progress: 0`: planejados, nunca
> executados.
>
> Este documento cruza o que aqueles planos já cobrem com o que o levantamento
> desta sessão acrescentou, e isola **o que sobra**.

---

## 1. O que N9–N12 já cobrem

| Plano | Blocos | Cobre |
|---|---|---|
| **N9 — conversa completa** | N9a mídia · N9b conversa real · N9c quadro operável · N9d ficha | Enviar anexo, ver/baixar mídia, gravar áudio; marcar lida, não lidas, presença, citação, ticks; **busca e filtros**, prioridade, atribuir, exportar, preview no cartão; campos personalizados, galeria, **linha do tempo**, catálogo de etiquetas, excluir nota. **Inclui o realtime do desktop** (`LocalEngineGateway`) |
| **N10 — IA analítica** | E1–E6 | Ligar o `Analyse`; assunto automático; etiquetagem por intenção; enriquecimento do contato por entidades; **upload de arquivo no treinamento**; **feedback do teste de resposta** |
| **N11 — operação e cadastros** | E1–E9 | Sonda de conexões (keepalive); **roteamento conexão → departamento**; detalhe da conexão; **whitelist**; **contatos e clientes PJ**; perfil do contato (nome e foto); **e-mail transacional**; **recuperação de senha e reenvio de convite**; residuais |
| **N12 — cutover** | E1–E5 | ETL contra dump de produção; validações da N7.5; enforce de quotas; janela de cutover |

### Os "residuais" da N11 (E9) cobrem mais do que o nome sugere

- `ReprocessarDeadLetter` na borda + tela `/admin/dead-letter`
- `LocalEngineFfiDataSource` no DI de produção
- **Job de expiração/aviso de assinatura** (`check_subscription_expirations`)
- Capacidade do atendente (`max_conversas`) na elegibilidade
- Normalizar `pollMessage`/`listMessage`/`buttonsMessage`
- CLI de export/import de `CoreSettings`

→ Isso **absorve o achado N1** do doc 31 (assinatura vencida não suspende) e os
itens #27, #31 e #33 do doc 26.

### E há material de pesquisa já coletado

`.context/plans/n9-conversa-completa/ref_evolution_go.md` (1067 linhas),
`ref_cloudflare_r2.md` (1138 linhas) e
`.context/plans/n11-operacao-cadastros/ref_email_transacional.md` (1021 linhas).
**Consultar antes de pesquisar qualquer coisa nessas frentes.**

---

## 2. O delta real — sete itens que nenhum plano cobre

Verificado por busca textual nos quatro planos e seus artefatos:

| # | Item | Origem | Severidade |
|---|---|---|---|
| **D1** | **Faixas de confiança e veto sobre o LLM** | F1 (doc 30) | 🔴 |
| **D2** | **Atribuição automática por rodízio** | F3 (doc 30) | 🔴 |
| **D3** | **Desligar o bot por instância e por conversa** | F2 (doc 30) / L7 (doc 29) | 🔴 |
| **D4** | **Fallback de escopos e papel somente-leitura** | L3 revisada (doc 29) | 🚨 segurança |
| **D5** | **Encerramento por inatividade** | F6 (doc 30), reclassificado | 🟡 |
| **D6** | **Notificar o atendente da atribuição** | F7 (doc 30), reclassificado | 🟡 |
| **D7** | **`PaymentRecord` e gestão global de usuários** | doc 31 §1 | 🟢 |

Busca que comprova a ausência (nos quatro planos e artefatos):
`resposta_bot`, `bot_pode_atender`, `confianca`, `confiabilidade`, `rodízio`,
`round-robin`, `inatividade`, `notificar o atendente`, `derivar_escopos`,
`somente-leitura`, `viewer`, `PaymentRecord` — **nenhuma ocorrência**.

> **D1+D2+D3 são o núcleo do produto**: o que decide se o bot responde, com que
> autoridade, e para quem a conversa vai quando ele não deve responder. É a maior
> lacuna funcional que restou, e nenhum plano a tinha.
>
> **D4 é segurança**: hoje qualquer não-admin nasce podendo escrever.

Esses sete viram o plano `regras-do-bot-e-permissoes`
(`.context/plans/regras-do-bot-e-permissoes.md`).

---

## 3. As correções — valor independente do plano

Estas não são lacunas; são **erros corrigidos** nos documentos de levantamento, e
valem para quem for executar N9–N12:

| Onde | Estava | É |
|---|---|---|
| doc 29, L3 | `module_permissions` é inerte | **É lido** — é a fonte dos escopos do JWT (`login.rs:244`). A lacuna é o *fallback* |
| doc 29, L4 | Não há editor de permissões | **Há** — as telas editam papel, escopos e fluxos; falta acabamento |
| doc 30, F1 | A v2 grava `confianca_resposta` | **Não grava.** `registrar_resposta_bot` só é chamado por teste |
| doc 30, F6 | A v1 encerrava por inatividade (30 min) | **Não encerrava.** Veio do diagrama; o checklist da v1 marca ❌ |
| doc 30, F7 | A v1 notificava o atendente | **Não notificava.** Mesmo checklist |
| 00-0609, D2 | Grupos viram atendimento | **Falso** — `evento_de_grupo` descarta na ingestão, com 8 testes |
| 00-0609, D3/D4 | Sem handler de conexão, sem keepalive | **Vencidos** — ambos existem hoje |
| 00-0609, O5 | Sem purga de mídia | **Falso** — `processar_midia_expirada`, 30 dias |
| 00-0609, C4 | Citação não está no proto | **Falso** — `admin.proto:514-516` |
| 00-0609, U4 | `module_permissions` inerte | **Falso** — mesmo erro da L3 |

E uma correção técnica que afeta a **N9a** diretamente:

> **`video_player` não suporta Windows.** O próprio plano N9 já registra isso e
> prevê um spike de `media_kit` no início da N9a. Qualquer material que liste
> `video_player` para o desktop está errado — inclusive o doc curado em
> `doc_dev/libs/flutter/video_player.md`, que não faz essa ressalva.

---

## 4. Achados técnicos que aceleram a execução de N9/N10

Levantados nesta sessão, com arquivo e linha. Não mudam o escopo dos planos —
encurtam a implementação.

### 4.1 O envio de mídia (N9a) está ligado nas duas pontas

```
data_postgres   grava `midia` no outbox                    ✅ atendimento.rs:557
worker          IGNORA e chama SendWhatsappMessage         ❌ main.rs:2584
data_whatsapp   handler_send_whatsapp_media                ✅ main.rs:1029
infra_evolution send_media → POST /send/media (com retry)  ✅ provider.rs:524
```

O comentário no `data_postgres` diz literalmente: *"O worker precisa saber que é
mídia para chamar SendWhatsappMedia em vez de SendWhatsappMessage"*.

**A ponte que falta:** o outbox dá **chave do R2**, o handler quer **URL**. A
conversão já existe e o worker já a usa no pipeline de entrada
(`main.rs:2008`): `PresignFile` no `storage_client`, com
`{file_name, expires_in}` — e há mock nos testes (`main.rs:3504`).

**Armadilha:** o worker tem retry próprio (`[0,1,2,4]` s) e o `send_media` do
provider tem outro (3 tentativas). Empilhar dá 12 tentativas. A mídia deve usar
**só** o do provider.

**Campos que o `/send/media` aceita e o nosso provider não manda.** A pesquisa
externa (fontes: [docs.evolutionfoundation.com.br](https://docs.evolutionfoundation.com.br/evolution-go/send-a-media-message),
coleção Postman, releases do GitHub) indica que o corpo aceita mais do que
`{number, type, url, caption}`:

| Campo | Serve para | Temos o dado? |
|---|---|---|
| `filename` | nome do arquivo exibido ao destinatário | ✅ **sim** — `midia.nome_arquivo`, hoje sem destino |
| `quoted` | citar a mensagem anterior | ✅ `mensagem_citada_id` já está no proto |
| `delay` | atraso antes de enviar | — |
| `mentionedJid` / `mentionAll` | menções em grupo | irrelevante (grupos são descartados) |

→ **`filename` é ganho barato**: o dado já viaja no outbox e hoje é jogado fora.
Um PDF chega ao cliente sem nome.

> ⚠️ A mesma pesquisa se contradiz sobre `quoted`: documenta o campo no corpo e,
> na tabela comparativa, afirma que o evolution-go **não** suporta citação
> (*"issue #27 aberto"*). **Não usar `quoted` sem testar.**

**`is_ptt` — a resposta apareceu, e não é onde se procurava.** Existe um endpoint
**separado**, `/message/sendWhatsAppAudio/{instance}`, distinto do `/send/media`.
Nenhum campo `ptt` foi encontrado no corpo do `/send/media`.

→ Áudio de voz não é "mais um campo": é **outro endpoint**, e exige método novo
no trait `MessagingProvider`. Confirmar empiricamente antes — pode ser que
`type: "audio"` já saia como voz.

### 4.2 Colunas vivas sem caminho de escrita

| Coluna | Situação |
|---|---|
| `confianca_resposta` | único `UPDATE` é chamado **só por teste** (`mensagens.rs:357` ← `tests/atendimentos/mod.rs:161`) |
| `data_primeira_resposta` | aparece em **5 `SELECT`s** e em nenhum `UPDATE` — sem ela não há SLA |
| `prioridade` | sem caminho de escrita |
| `bot_pode_atender` | só desliga (`atendimentos.rs:461`); **nada** devolve para `true` |

### 4.3 Realtime não tem destinatário

Canal `tenant:{id}:events`, um para a empresa toda. `AtendimentoEvent`
(`admin.proto:1289`) tem três campos: `event_type`, `tenant_id`, `payload`.
Tipos publicados: `whatsapp.conexao`, `whatsapp.presenca`, `kanban.movido`,
`mensagem.recebida`, `mensagem.enviada`, `mensagem.status_atualizado`.

→ **Nenhum evento de atribuição.** É o que trava o D6 e exige decisão de
contrato antes de qualquer código.

### 4.4 Vocabulário de auditoria já estabelecido

`atendimento.aberto` · `atendimento.feedback_expirado` ·
`atendimento.transferido_por_ia` · `bot.degradado` · **`bot.respondeu`** ·
**`bot.silenciado`** · `kanban.movido` · `mensagem.confirmada` ·
`mensagem.enviada` · `mensagem.envio_falhou` · `mensagem.falha_persistencia` ·
`mensagem.persistida` · `midia.analisada` · `midia.purgada` ·
`ticket.transicionado` · `webhook.received/duplicated/ignored/rejected`

Reusar antes de criar sinônimo. **`bot.silenciado` já existe** e serve ao D3.

### 4.5 Restrição de ambiente para a N11-E7 (e-mail)

**Sobre a porta 25 há um conflito de fontes que não escondo:**

- a base de suporte da Hostinger diz literalmente *"we do not block the SMTP 25
  port"*, com limite de **5 e-mails/minuto**
  ([fonte](https://www.hostinger.com/support/7854530-is-smtp-port-25-blocked-on-hostinger-vps/));
- a pesquisa complementar leu o mesmo limite como bloqueio de fato, e reporta
  **465 e 587 abertas**.

→ **Convergem no que importa:** a 25 é inutilizável no volume de rajada (5/min),
e 465/587 estão disponíveis. **Testar as três portas no VPS antes de decidir** —
custa um `nc -zv`.

**A decisão real é de entregabilidade, não de porta.** IP de VPS tem má
reputação por origem; e desde nov/2025 Gmail e Yahoo rejeitam de forma dura quem
falha SPF/DKIM/DMARC. Reputação de IP é trabalho recorrente que uma manutenção
solo não sustenta — e o modo de falha é silencioso: o log diz `250 OK` e o
convite morre no spam.

**Recomendação: relay via provedor.** Entre os dois:

| | Amazon SES | Resend |
|---|---|---|
| Início | **sandbox**: 200/dia, 1/s, só para endereços verificados; sair leva ~24 h e ticket | sem sandbox — produção desde o dia 1 |
| Free tier | **removido em jul/2026**; agora ~US$ 0,10 por 1000 | ~3000/mês e 100/dia |
| SDK Rust | `aws-sdk-rust` (a família já é usada no projeto) | `resend-rs`, oficial |
| Esforço | médio | baixo |

**Resend**, pelo caminho mais curto até funcionar — o sandbox do SES bloqueia
justamente o teste de convite com usuário real, que é o que se quer validar. E
`lettre` (0.11.22, doc curado) continua servindo: os dois oferecem endpoint
SMTP, então a interface fica trocável.

> ⚠️ **Números de preço e free tier vêm de pesquisa de agente e não foram
> confirmados em fonte oficial nesta sessão.** Conferir em `resend.com/pricing`
> e `docs.aws.amazon.com/ses` na fase P antes de fechar.
>
> E consultar `ref_email_transacional.md` (1021 linhas, já coletado na N11)
> **antes** de pesquisar de novo.

---

## 5. Ordem sugerida

```
regras-do-bot-e-permissoes   (D4 primeiro — é segurança; depois D1+D2+D3)
N9a  mídia                   (o fio solto do §4.1 é a maior relação impacto/esforço)
N9b/N9c/N9d                  conversa, quadro e ficha
N10                          IA analítica (paralelizável com N11)
N11                          operação e cadastros (E7 e-mail tem lead time de DNS: começar no dia 1)
cadastro-retomavel-e-pagamento
N12                          cutover
```

**D4 antes de tudo:** é a única frente com risco de segurança ativo, e mexer em
permissão depois que a equipe cresceu é mais caro.

**N11-E7 em paralelo desde o dia 1:** DKIM leva 24–48 h para propagar; é o item
de maior lead time de todo o backlog, e o próprio plano N11 já avisa isso.
