# Mapa de telas, rotas e funcionalidades — desenho da v2

> **Data:** 2026-08-09 · **Origem:** varredura dos **40 templates HTML**, 16
> partials e 10 componentes da v1 (`modules/design_system/templates/`), das suas
> views e das ~100 rotas, cruzada com as **30 rotas Flutter** e os **84 RPCs** da
> v2. Terceira passada da auditoria — as duas primeiras estão em
> [26-levantamento-paridade-v1-v2.md](./26-levantamento-paridade-v1-v2.md).
>
> **Objetivo:** não é copiar a v1 tela a tela. É saber **tudo que ela faz** para
> desenhar a v2 com telas por caso de uso, e ter, para cada tela, a lista fechada
> de dados, ações e RPCs — o que existe e o que falta.

---

## Como ler

- **Parte A** — inventário das páginas da v1, com as ações reais de cada uma.
- **Parte B** — as rotas que a v2 já tem.
- **Parte C** — o mapa de navegação proposto (o desenho adaptado).
- **Parte D** — ficha por tela: rota, persona, dados, ações, RPCs, estado.
- **Parte E** — contratos novos consolidados (o que entrar no `.proto`).
- **Parte F** — ordem de implementação, ligada às fases N8.5–N12.

Estado por tela: ✅ existe e cobre · ⚠️ existe e falta parte · 🆕 não existe ·
🚫 não será portada.

---

# Parte A — O que a v1 tem (páginas reais)

## A.1 Públicas (sem sessão) — 5 páginas

| Página | Rota v1 | O que faz |
|---|---|---|
| Landing | `/` | apresentação do produto |
| Login | `/usuarios/login/` | e-mail + senha |
| Cadastro | `/usuarios/cadastro/` | criação de usuário |
| Recuperação de senha | 4 rotas (`form`, `done`, `confirm`, `complete`) | fluxo completo com e-mail |
| Ativação de conta | `/tenants/activate/<token>/` | convidado define senha e entra |

Estados auxiliares: `403`, `404`, `500`, `tenant_not_found`, `subscription_expired`,
`invite_expired`, `workspace_disabled` (feature flag).

## A.2 Onboarding do tenant — 5 páginas

| Página | O que faz |
|---|---|
| `signup` | criação do tenant |
| `step_1_tenant` | dados da empresa (+ `api_check_slug` ao vivo) |
| `step_2_payment` | pagamento |
| `step_3_config` | configuração inicial |
| `step_4_provision` | provisionamento (espera ativa) |
| `email_access_code` | e-mail com código de acesso |

## A.3 Workspace — **a tela-mãe** (1 página, 16 partials)

Uma rota (`/workspace/`) que concentra quadro, conversa e ficha. É a tela mais
densa da v1 e a que mais distância tem da v2. Inventário completo do que ela faz:

### Topbar

| Elemento | Detalhe |
|---|---|
| Voltar ao painel | link para o dashboard |
| **Seletor de fluxo** | lista `nome — departamento`; troca o quadro |
| **Modos de foco** | segmented control: quadro / dividido / conversa |
| **Busca global** | campo com atalho `⌘K` (debounce 300 ms) |
| **Popover de filtros** | busca, **prioridade**, **etiqueta**, **apenas não lidos** — com contador de filtros ativos |
| **Exportar CSV** | do fluxo corrente |
| **Sino de notificações** | contador de mensagens não lidas; clique filtra por não lidas |
| **Pílula de tempo real** | conectado / desconectado (SSE) |
| Identidade | nome do atendente + sair |

### Quadro (kanban)

| Elemento | Detalhe |
|---|---|
| Colunas | etapa do fluxo, com **contador** por coluna e estado vazio |
| Arrastar | `Sortable.js`, move entre colunas |
| **Cartão** | avatar (foto do WhatsApp), nome, **emoji de canal**, **emoji + texto de status**, tempo desde a última mensagem, **badge de não lidas**, assunto, **preview da última mensagem** (com `↳` quando foi do atendente), **chip de prioridade** colorido, avatar + nome do atendente |

### Conversa

| Elemento | Detalhe |
|---|---|
| Cabeçalho | avatar com foto, nome, **presença do contato** (`✍️ digitando` / `🎤 gravando`), telefone, etapa atual |
| Ações rápidas | **Transferir** (popover com fluxos disponíveis), **Nota**, **Etiqueta** (popover com o catálogo, marca as aplicadas, contador) |
| Corpo | **separador por dia**, agrupamento de bolhas consecutivas, botão flutuante "ir para o fim" |
| **Bolha** | citação (quoted) com preview; **imagem** clicável; **áudio** com player, marca de PTT e duração; **vídeo** com duração; **documento** com extensão, nome, tamanho, ver-PDF e baixar; **toggle "Ver análise IA"** (transcrição + resumo); hora; **ticks de status** (pendente/enviado/entregue/lido/falhou) |
| **Composer** | anexo (imagem, vídeo, áudio, PDF, doc, docx, xls, xlsx), **gravação de voz** (timer, cancelar, enviar), **responder** (banner de citação), Enter envia / Shift+Enter quebra linha, dispara presença ao digitar |
| **Lightbox** | imagem, vídeo e PDF em tela cheia, com download |
| Mini-bar | conversa reduzida quando o foco é o quadro |

### Ficha do atendimento (drawer)

| Seção | Conteúdo |
|---|---|
| Cabeçalho | avatar 76 px, nome, telefone, **chips de etiquetas aplicadas** |
| Dados do contato | nome, telefone, e-mail, status, **prioridade**, atendente, assunto, tags |
| **Campos personalizados** | valor, **origem (BOT / MANUAL / IMPORT)**, **barra de confiança da IA em %**, **edição inline** |
| **Mídia & arquivos** | galeria dos 6 últimos, com thumb de imagem/vídeo e ícone de documento |
| **Linha do tempo** | eventos tipados: label, descrição, **autor**, data/hora |
| Notas internas | lista + criar + excluir |

### Atalhos de teclado

`Alt+1` quadro · `Alt+2` dividido · `Alt+3` conversa · `Esc` reduzir foco ·
`i` ficha · `⌘K` busca. Hint visível nos primeiros 5 s.

## A.4 Configuração — 9 páginas

| Página | Ações |
|---|---|
| `dashboard` (tenant) | cartões de status de cada integração (banco, Evolution, Trello, IA, debug) com atalho para configurar |
| `config_ai` | `dados_empresa`, `persona_bot`, `bot_agent_name`, **`msg_fallback`**, **`msg_sem_info`**, `msg_transferencia`, **`entity_types`**, provedores e modelos (LLM, transcrição, visão), chaves de API |
| `config_evolution` | URL do servidor, nome da instância, testar conexão |
| `config_database` | 🚫 host/porta/base/usuário/SSL + rodar migrations + testar |
| `config_trello` | 🚫 chave/segredo/token/workspace + registrar e remover webhook |
| `config_debug` | 🚫 dump das configs carregadas |
| `instance_list` | lista com nome, status, telefone, **departamento vinculado**; criar, **atualizar todas**, ir para departamentos e atendentes |
| `instance_detail` | **QR com polling** (iniciar/parar), **logout**, **configurar webhook** (com copiar URL), **excluir** (zona de perigo), instance id, telefone, criado em, última verificação |
| `whitelist` (+ form + confirm) | listar com **busca**, adicionar, editar, **ativar/desativar**, excluir com confirmação |

## A.5 Treinamento — 6 páginas

| Página | Ações |
|---|---|
| `treinar_ia` | tag, grupo, conteúdo **ou upload de documento** (7 formatos) |
| `pre_processamento` | revisar o texto melhorado pela IA antes de aceitar |
| `verificar_treinamentos` | lista com ação por item (finalizar, remover) |
| `cadastrar_query_compose` | tag, grupo, descrição, exemplo, comportamento |
| `verificar_query_compose` | lista de intents com ação por item |
| `testar_query` | pergunta **ou mídia anexada**, resposta, **campo "resposta correta"** e registro de feedback |

## A.6 Usuários e permissões — 4 páginas

| Página | Ações |
|---|---|
| `users/list` | membros e convites pendentes, com **reenviar convite** |
| `users/invite` | e-mail, nome, **módulos** (8) e **fluxos** (agrupados por departamento) |
| `users/edit_permissions` | mesma matriz, para um membro existente |
| `users/activate` | convidado define a senha |

**Módulos de permissão da v1 (8):** `painel_admin`, `clientes`, `operacional`,
`treinamento`, `atendimentos`, `atendimento` (workspace), `configuracoes`,
`usuarios`. **Papéis (4):** admin, manager, staff, viewer.

## A.7 Backoffice (superusuário) — 2 páginas + admin do Django

| Página | Conteúdo |
|---|---|
| `backoffice/dashboard` | **assinaturas expirando nos próximos 7 dias**, tenants recentes |
| `backoffice/register_payment` | valor, data, método, observações |
| `admin/` + `tenant-admin/` | 🚫 CRUD genérico de 21 modelos |

---

# Parte B — O que a v2 tem hoje

**App do tenant (`smart-core-tenant`) — 22 rotas**

`/` · `/login` · `/cadastro` `/cadastro/plano` `/cadastro/pagamento`
`/cadastro/pronto` · `/configuracao/assistente` `/configuracao/whatsapp`
`/configuracao/departamento` · `/atendimentos` (quadro + conversa) ·
`/tenant/painel` `/tenant/conexoes` `/tenant/equipe` `/tenant/fluxos`
`/tenant/fluxos/:id/etapas` `/tenant/contatos` `/tenant/treinamento`
`/tenant/convites` `/tenant/usuarios` `/tenant/config` · `/home` `/extra`

**App do superusuário (`smart-core-admin`) — 8 rotas**

`/admin/dashboard` `/admin/tenants` `/admin/billing` `/admin/audit`
`/admin/core-settings` `/admin/evolution` `/admin/feature-flags`
`/admin/tenant-config`

---

# Parte C — Mapa de navegação proposto

## Princípios da adaptação

1. **Tela por caso de uso, não por tabela.** A v1 tinha 6 telas de treinamento
   porque espelhava o ciclo do banco; a v2 tem uma com três abas. Mantém-se.
2. **O workspace continua sendo uma tela só.** Quadro, conversa e ficha no mesmo
   lugar, com modos de foco — é o desenho certo e a v2 já foi por ele.
3. **Configuração é uma tela com abas**, não seis cartões que levam a seis telas.
   Some `config_database`, `config_trello` e `config_debug` (base única, quadro
   próprio, sem dump de config em produção).
4. **Nada de CRUD genérico.** O que o `tenant-admin` do Django resolvia por
   tabela vira tela de caso de uso (whitelist, campos personalizados, clientes).
5. **Desktop e Web pelo mesmo código** — nenhuma tela pode depender de recurso
   que só existe num dos dois; gravação de áudio e anexo precisam de fallback.

## Árvore — app do tenant

```
/login                      público
/recuperar-senha            público            🆕
/redefinir-senha/:token     público            🆕
/aceitar-convite?token=     público            ✅
/cadastro/…                 público (4 passos) ✅
/configuracao/…             pós-cadastro (3)   ✅

/tenant/painel              início                       ✅
/atendimentos               WORKSPACE (quadro+chat+ficha) ⚠️
   ├── ?fluxo=:id           seletor de fluxo             ✅
   ├── ?foco=quadro|split|chat                           🆕
   └── ?busca= &prioridade= &etiqueta= &atendente= &nao_lidos=  🆕

/tenant/contatos            lista + busca                ✅
   ├── /:id                 ficha do contato + histórico 🆕
   └── /clientes            empresas (PJ)                🆕
/tenant/equipe              departamentos + atendentes   ✅
/tenant/fluxos              fluxos                       ✅
   ├── /:id/etapas          etapas                       ✅
   └── /:id/campos          campos personalizados        🆕
/tenant/etiquetas           catálogo de etiquetas        🆕
/tenant/conexoes            conexões de WhatsApp         ⚠️
   └── /:id                 detalhe: QR, bot, webhook    🆕
/tenant/whitelist           lista de números permitidos  🆕
/tenant/treinamento         material · intenções · teste ⚠️
/tenant/usuarios            membros e permissões         ✅
/tenant/convites            convites                     ⚠️
/tenant/config              abas: assistente · mensagens · marca · IA ⚠️
```

## Árvore — app do superusuário

```
/admin/dashboard         resumo + assinaturas expirando  ⚠️
/admin/tenants           tenants → detalhe               ✅
/admin/billing           planos, assinaturas, pagamentos, vouchers ✅
/admin/evolution         instâncias de todos os tenants  ✅
/admin/core-settings     configuração global             ⚠️
/admin/feature-flags     flags e overrides               ✅
/admin/audit             trilha de auditoria             ✅
/admin/tenant-config     config de um tenant             ✅
/admin/dead-letter       mensagens sem destino           🆕
```

---

# Parte D — Ficha por tela

## D.1 `/atendimentos` — Workspace ⚠️

**Persona:** atendente e admin do tenant. **RBAC:** módulo `atendimento`, filtrado
por `flow_permissions`.

### Já funciona

Colunas vindas do fluxo, arrastar com regras de transição conferidas contra a v1,
assumir ao arrastar (desliga o bot e saúda), chat em streaming com reconexão,
enviar texto, ficha com etiquetas e notas, selo "gerado por IA", resumo de mídia.

### Falta — quadro

| Item | RPC | Estado |
|---|---|---|
| Busca por nome/perfil/telefone/assunto | estender `ListAtendimentos` (`q`) | 🆕 aditivo |
| Filtros: prioridade, etiqueta, atendente, apenas não lidos | estender `ListAtendimentos` | 🆕 aditivo |
| Paginação | `offset` em `ListAtendimentos` | 🆕 aditivo |
| Contador de não lidas por cartão e global | `GetNaoLidas` + campo no resumo | 🆕 |
| Preview da última mensagem no cartão | campo em `AtendimentoResumo` | 🆕 aditivo |
| Chip de prioridade + alterar | `DefinirPrioridadeAtendimento` | 🆕 |
| Atribuir a outro atendente | `AtribuirAtendimento` | 🆕 |
| Exportar CSV do quadro | `ExportAtendimentosCsv` (stream) | 🆕 |
| Foto do contato no cartão e no chat | `GetWhatsappProfilePicture` 🔌 + campo | 🆕 |
| Modos de foco e atalhos de teclado | só cliente | 🆕 |

### Falta — conversa

| Item | RPC | Estado |
|---|---|---|
| **Enviar mídia** (anexo) | `EnviarMidiaAtendimento` → `data_storage` + 🔌 `SendWhatsappMedia` | 🆕 |
| **Gravar áudio** e enviar | mesmo RPC, `tipo=audio` (PTT) | 🆕 |
| **Ver/baixar mídia recebida** | `midia` em `MensagemThread` (URL pré-assinada) | 🆕 |
| Lightbox de imagem/vídeo/PDF | só cliente | 🆕 |
| Player de áudio com duração e marca de PTT | metadados na mensagem | 🆕 |
| **Marcar como lida** | `MarcarAtendimentoLido` + 🔌 `MarkWhatsappMessageRead` | 🆕 |
| **Presença "digitando"** | `DefinirPresencaAtendimento` + 🔌 `SetWhatsappPresence` | 🆕 |
| Presença **do contato** no cabeçalho | consumir evento `PRESENCE` (N8.5.5) | 🆕 |
| **Responder mensagem** (citação) | `mensagem_citada_id` no envio + `quoted` na thread | 🆕 aditivo |
| Ticks de entrega/leitura | `data_entregue`/`data_lida` na thread | 🆕 aditivo |
| Separador de dia e agrupamento | só cliente | 🆕 |
| Transferir de fluxo pela conversa | expor `TransferirAtendimentoParaFluxo` 🔌 | 🆕 |

### Falta — ficha

| Item | RPC | Estado |
|---|---|---|
| Dados do contato na ficha | estender `GetDetalheAtendimento` | ⚠️ |
| **Campos personalizados** com origem e confiança | `ResolverCamposAtendimento` 🔌 + `SetValorCampoAtendimento` | 🆕 |
| **Galeria de mídias** | `ListarMidiasAtendimento` | 🆕 |
| **Linha do tempo** | `ListarMovimentosAtendimento` | 🆕 |
| Excluir nota | `RemoverNota` | 🆕 |

## D.2 `/tenant/conexoes` e `/tenant/conexoes/:id` ⚠️ 🆕

**Persona:** admin do tenant.

Hoje: listar, reconectar, remover. **Falta a tela de detalhe inteira**, que na v1
é onde a conexão se resolve:

| Item | RPC | Estado |
|---|---|---|
| **QR com polling** fora do onboarding | `GetMyWhatsappInstanceQrCode` | 🆕 |
| **Ligar/desligar o bot** por conexão | `SetMyWhatsappInstanceBot` | 🆕 |
| **Vincular ao departamento** (`AppInstance`) | `SetMyWhatsappInstanceDepartamento` | 🆕 (é o que destrava o roteamento — N11.2) |
| Renomear | `RenameMyWhatsappInstance` | 🆕 |
| Configurar webhook (com copiar URL) | `SetMyWhatsappInstanceWebhook` | 🆕 |
| Logout da sessão | `LogoutMyWhatsappInstance` | 🆕 |
| Metadados (instance id, telefone, criada em, última verificação) | estender status | ⚠️ |

## D.3 `/tenant/contatos`, `/:id` e `/clientes` ⚠️ 🆕

| Item | RPC | Estado |
|---|---|---|
| Lista com busca | `ListMyContatos` | ✅ |
| **Ficha do contato** (editar nome, e-mail, tags) | `UpdateMyContato` | 🆕 |
| **Histórico de atendimentos** do contato | `ListAtendimentosDoContato` | 🆕 |
| **Empresas (PJ)**: CRUD | `ListMyClientes`, `CreateMyCliente`, `UpdateMyCliente`, `DesativarMyCliente` | 🆕 (🔌 repo pronto) |
| Vincular contato ↔ empresa | `VincularContatoCliente` / `DesvincularContatoCliente` | 🆕 (🔌 repo pronto) |

## D.4 `/tenant/whitelist` 🆕

Tela nova. O servidor já sabe consultar (`IsPhoneWhitelisted` no
`webhook_ingress`); falta a gestão.

| Item | RPC |
|---|---|
| Listar com busca | `ListMyWhitelist` |
| Adicionar (nome + telefone) | `AddMyWhitelist` |
| Editar | `UpdateMyWhitelist` |
| Ativar/desativar | `ToggleMyWhitelist` |
| Remover (com confirmação) | `RemoveMyWhitelist` |

## D.5 `/tenant/fluxos/:id/campos` 🆕

Catálogo de campos personalizados por fluxo — o que alimenta a ficha e o
`Responder`.

| Item | RPC |
|---|---|
| Listar campos do escopo | `ListMyCamposPersonalizados` |
| Criar (nome, slug, tipo, obrigatório, ordem, hint) | `CreateMyCampoPersonalizado` |
| Editar | `UpdateMyCampoPersonalizado` |
| Desativar | `DesativarMyCampoPersonalizado` |

## D.6 `/tenant/etiquetas` 🆕

Hoje só dá para criar etiqueta de dentro da ficha, e não há como corrigir uma.

| Item | RPC | Estado |
|---|---|---|
| Listar catálogo | parte de `GetDetalheAtendimento` | ⚠️ separar |
| Criar | `CreateEtiqueta` | ✅ |
| Editar (nome, cor, descrição) | `UpdateEtiqueta` | 🆕 |
| Desativar | `DesativarEtiqueta` | 🆕 |

## D.7 `/tenant/treinamento` ⚠️

| Item | RPC | Estado |
|---|---|---|
| Material: listar, criar, revisar, finalizar, remover | 5 RPCs | ✅ |
| Intenções: CRUD | 4 RPCs | ✅ |
| Testar pergunta com trechos e semelhança | `TestarPergunta` | ✅ |
| **Upload de arquivo** (7 formatos) | `CreateMyTreinamentoComArquivo` + extração no `ia_engine` | 🆕 |
| **Testar com mídia** anexada | estender `TestarPergunta` | 🆕 |
| **Feedback com resposta correta** | `RegistrarFeedbackTeste` | 🆕 |

## D.8 `/tenant/config` ⚠️

Abas propostas: **Assistente** (persona, nome do agente, dados da empresa) ·
**Mensagens automáticas** (`msg_fallback`, `msg_sem_info`, `msg_transferencia`) ·
**Marca** (nome, cores, fuso, idioma) · **IA** (provedores, modelos, chaves,
`entity_types`, prompts).

| Item | Estado |
|---|---|
| Persona, nome do agente, provedores, modelos, chaves | ✅ |
| `msg_fallback` / `msg_sem_info` — **passar a ter efeito** | ⚠️ N8.5.4 |
| `entity_types` (depende do `Analyse`) | ⚠️ N10.1 |
| Prompts (`prompts` JSONB) na UI | 🆕 |
| Marca: nome, cores, fuso, idioma | 🆕 |

## D.9 `/tenant/painel` ✅ · `/tenant/usuarios` ✅ · `/tenant/convites` ⚠️

Painel e usuários cobrem a v1. Convites: falta **reenviar** (`ReenviarConvite`) e
**entrega por e-mail** — hoje o link é relativo, exibido para copiar.

## D.10 Públicas 🆕

| Item | RPC |
|---|---|
| Recuperar senha (pedir) | `SolicitarRedefinicaoSenha` |
| Redefinir senha (token) | `RedefinirSenha` |
| Entrega de e-mail (convite, ativação, recuperação) | porta de e-mail no servidor |

## D.11 Admin — `/admin/dashboard` ⚠️ e `/admin/dead-letter` 🆕

| Item | RPC | Estado |
|---|---|---|
| Resumo | `GetDashboardSummary` | ✅ |
| **Assinaturas expirando (7 dias)** | estender o resumo | 🆕 |
| Mensagens sem destino | expor `ReprocessarDeadLetter` 🔌 | 🆕 |
| Export/import de `CoreSettings` | CLI no `control_plane` | 🆕 |

---

# Parte E — Contratos novos consolidados

**43 RPCs novos** e **6 extensões aditivas**. Agrupados por ciclo:

### Conversa (16)
`EnviarMidiaAtendimento` · `ListarMidiasAtendimento` · `MarcarAtendimentoLido` ·
`GetNaoLidas` · `DefinirPresencaAtendimento` · `ListarMovimentosAtendimento` ·
`SetValorCampoAtendimento` · `RemoverNota` · `UpdateEtiqueta` ·
`DesativarEtiqueta` · `AtribuirAtendimento` · `DefinirPrioridadeAtendimento` ·
`TransferirMeuAtendimentoParaFluxo` · `ExportAtendimentosCsv` ·
`ListMyCamposPersonalizados` + 3 do CRUD de campo

### Conexões (6)
`GetMyWhatsappInstanceQrCode` · `SetMyWhatsappInstanceBot` ·
`SetMyWhatsappInstanceDepartamento` · `RenameMyWhatsappInstance` ·
`SetMyWhatsappInstanceWebhook` · `LogoutMyWhatsappInstance`

### Cadastros (11)
`UpdateMyContato` · `ListAtendimentosDoContato` · `ListMyClientes` ·
`CreateMyCliente` · `UpdateMyCliente` · `DesativarMyCliente` ·
`VincularContatoCliente` · `DesvincularContatoCliente` · `ListMyWhitelist` +
4 do CRUD de whitelist

### Treinamento e IA (3)
`CreateMyTreinamentoComArquivo` · `RegistrarFeedbackTeste` · extensão de
`TestarPergunta` com mídia

### Auth e admin (4)
`SolicitarRedefinicaoSenha` · `RedefinirSenha` · `ReenviarConvite` ·
`ReprocessarDeadLetter` na borda

### Extensões aditivas (6)
`ListAtendimentosRequest` (`q`, `prioridade`, `etiqueta_id`, `atendente_id`,
`apenas_nao_lidos`, `offset`) · `AtendimentoResumo` (preview, não lidas, foto,
prioridade) · `MensagemThread` (mídia, citação, entregue/lida) ·
`SendOutboundMessageRequest` (`mensagem_citada_id`) · `GetDetalheAtendimento`
(contato, campos) · `GetDashboardSummary` (assinaturas expirando)

> **Regra do projeto:** evolução **aditiva** — campo novo nunca renumera nem
> reusa número liberado (ver `reserved` no `ai_engine.proto`). E todo RPC exposto
> ao Flutter precisa de **método concreto no `grpc_web.rs`**: sem ele, a rota
> responde no `data_postgres` e o cliente não alcança.

---

# Parte F — Ordem de implementação

Ligada às fases de [02-fases-desenvolvimento.md](./02-fases-desenvolvimento.md):

| Ciclo | Telas | Por que nesta ordem |
|---|---|---|
| **N8.5** | nenhuma (só servidor) | são defeitos em caminho que já roda |
| **N9a** | Workspace — mídia (enviar, ver, gravar, lightbox) | é a lacuna que o atendente sente em toda conversa |
| **N9b** | Workspace — leitura, não lidas, presença, citação, ticks | fecha a conversa como canal de verdade |
| **N9c** | Workspace — busca, filtros, prioridade, atribuir, exportar | torna o quadro operável com volume |
| **N9d** | Ficha — campos personalizados, galeria, timeline; `/tenant/fluxos/:id/campos`; `/tenant/etiquetas` | o que se sabe da conversa |
| **N10** | Treinamento (arquivo, teste com mídia, feedback) | depende do `ia_engine`, não do chat |
| **N11a** | `/tenant/conexoes/:id` completo + whitelist | destrava operar o WhatsApp sozinho |
| **N11b** | Contatos (ficha, histórico) + clientes PJ | cadastro completo |
| **N11c** | Recuperar senha + e-mail transacional + reenviar convite | tira o suporte manual do caminho |
| **N12** | `/admin/dead-letter`, assinaturas expirando | operação antes do cutover |

**Regra de execução por tela** (a que evitou retrabalho nas rodadas anteriores):
contrato → servidor (repositório com query validada contra o banco real, port,
adapter, handler com auditoria) → **método concreto no `grpc_web.rs`** → stubs
Dart → módulo cliente no padrão RSOE, registrado no workspace, no bootstrap e no
`test-flutter.ps1` → testes de domínio, tradução de erro e regressão.

---

*Levantamento de telas realizado em 2026-08-09 sobre `dev` @ `cf30905`.*
