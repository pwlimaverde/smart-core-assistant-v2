# N11 — Operação da conexão, roteamento e cadastros

> **Origem:** `26-levantamento-paridade-v1-v2.md` §3.4/§3.7 e
> `27-mapa-telas-rotas-v2.md` §D.2/D.3/D.4/D.10.
> **Tese:** o tenant precisa operar sozinho o que hoje exige acesso ao banco ou
> ao painel legado.
> **Escala:** LARGE · **Depende de:** N8.5 (evento `CONNECTION`).
> Paralelizável com N10.
> **Apoio:** `info_aux_n11-operacao-cadastros.md`, `ref_evolution_go.md`,
> `ref_email_transacional.md`.

---

## E1 — Sonda de estado das conexões (o "keepalive" da v1, revisto)

### O contexto

A v1 rodava `keepalive_evolution_instances` a cada **60 s** com o comentário: *"o
servidor whatsmeow derruba a conexão quando ociosa; reconectamos a cada 60s para
não perder webhooks"*. A v2 não tem nada equivalente.

**Correção da premissa** (pesquisa desta rodada): a evolution-go/whatsmeow **tem
keep-alive de socket nativo** e reconexão automática com backoff. O que se
recomenda de fora é **sondar o estado** (`GET /instance/status` — path real do
projeto) periodicamente, não forçar reconexão. Reconectar às cegas a cada minuto
pode inclusive derrubar sessão saudável.

### O que fazer

Job novo no scheduler do worker (quinto, no padrão dos existentes: lock no
Redis, lote, varredura cross-tenant com `admin_pool`):

- intervalo configurável, default **30 s**;
- para cada instância ativa: consultar estado e persistir via
  `AtualizarEstadoInstancia`;
- **só tentar reconectar** quando o estado for `disconnected` por N sondagens
  consecutivas (histerese) — nunca no primeiro sinal, porque `unknown` já é
  tratado como situação própria ("sem resposta") desde a etapa 1 da paridade;
- respeitar o teto de ~50 req/s por instância (ver `info_aux`).

Combinado com o consumo do evento `CONNECTION` (N8.5.5), o estado passa a ser
atualizado por **push** (imediato) e conferido por **pull** (rede de segurança).

### Observabilidade & Auditoria

- **Logs:** span `whatsapp.sonda_estado` com `instancias_verificadas`,
  `mudancas`, `duracao_ms`. Varredura sem mudança **não** loga em INFO (o
  scheduler já segue essa regra: varredura vazia não audita).
- **Auditoria:** `whatsapp_instance.state_updated` (já existe) quando o estado
  muda, com `origem="sonda"` para distinguir do push do webhook. **Sim**: queda
  de conexão é o evento operacional que explica perda de mensagem.
  Reconexão automática audita `whatsapp_instance.reconectada`.
- **Sanitização:** a `api_key` da instância é cifrada em repouso (migration
  0023) e **nunca** entra em log — usar `SecretString` no caminho da sonda.

---

## E2 — Roteamento por conexão → departamento (`AppInstance`)

### O defeito

`resolver_atendimento_para_contato` (`data_postgres/src/adapters/atendimento.rs:346`)
resolve o fluxo com `buscar_primeiro_ativo` — **o primeiro fluxo ativo do
tenant**. A v1 mapeava `api_key` da instância → `Departamento`
(`Departamento.validar_api_key`, `_configure_department_from_app_instance`).

Tenant com duas conexões (Vendas e Suporte) manda tudo para o mesmo lugar. A
tabela `oraculo_app_instance` existe na v2 (migration 0005) e **não é usada**.

### O que fazer

1. **Vincular**: `SetMyWhatsappInstanceDepartamento(instance_id, departamento_id)`
   + seleção na tela de detalhe da conexão (E3).
2. **Rotear**: em `resolver_atendimento_para_contato`, quando o evento traz a
   instância (e traz — o `webhook_ingress` já resolve `instance_id`), buscar o
   departamento vinculado e, dele, o fluxo. **Fallback** para o primeiro fluxo
   ativo quando não houver vínculo — comportamento de hoje, para não quebrar
   quem já opera.
3. **Feature flag** por tenant para o rollout (`roteamento_por_instancia`), com
   reversão imediata se algo sair errado.

**É a alteração de maior risco de regressão do backlog** — mexe em qual fila a
conversa cai.

### Observabilidade & Auditoria

- **Logs:** campo `origem_fluxo` = `instancia` | `fallback` no span de resolução.
  É o que permite ver em produção quantos tenants ainda dependem do fallback.
- **Auditoria:** `whatsapp_instance.departamento_vinculado` na mudança de
  vínculo (é configuração que muda roteamento). A resolução em si não audita
  (alto volume) — **intencional**.
- **Sanitização:** sem PII nova.

### Testes

Duas instâncias em departamentos distintos → conversas em fluxos distintos.
Instância sem vínculo → fallback (regressão). Departamento desativado → fallback
com WARN. Teste e2e com dois números.

---

## E3 — Tela de detalhe da conexão

Hoje `/tenant/conexoes` lista, reconecta e remove. Falta o detalhe — que na v1
(`instance_detail.html`) é onde a conexão se resolve.

| Ação | RPC novo | Endpoint real (evolution-go) |
|---|---|---|
| Ver QR com polling | `GetMyWhatsappInstanceQrCode` | `GET /instance/qr` (**QR é imagem base64**) |
| Ligar/desligar bot | `SetMyWhatsappInstanceBot` | — (coluna própria, não é da Evolution) |
| Vincular departamento | `SetMyWhatsappInstanceDepartamento` | — (E2) |
| Renomear | `RenameMyWhatsappInstance` | — |
| Configurar webhook | `SetMyWhatsappInstanceWebhook` | ver `provider.rs` (`advanced-settings`) |
| Logout da sessão | `LogoutMyWhatsappInstance` | `DELETE /instance/logout` |

Mais os metadados que a v1 mostra: instance id (com copiar), telefone, criada em,
última verificação. E "zona de perigo" para excluir, com confirmação.

**Reaproveitar o polling de QR do onboarding** — já resolvido lá (commits
`dba254b`, `e780e92`, `1503583`, incluindo o bug do polling derrubando a sessão
recém-pareada). **Não reimplementar**: extrair para componente compartilhado.

### Observabilidade & Auditoria

- **Logs:** spans por ação, com `instance_id`.
- **Auditoria:** **sim para todas** — `whatsapp_instance.bot_alterado`,
  `.renomeada`, `.webhook_alterado`, `.logout`, `.deletada` (esta já existe).
  São mudanças de configuração operacional com efeito imediato no atendimento.
- **Sanitização:** o QR é **credencial de pareamento** — nunca logar a imagem
  nem o payload; o token de webhook idem.

---

## E4 — Whitelist

Tela nova `/tenant/whitelist`. O `webhook_ingress` já consulta
(`IsPhoneWhitelisted`) e o repositório existe (`integracoes/whitelist.rs`) —
falta a gestão, que na v1 são 5 rotas.

`ListMyWhitelist` (com busca), `AddMyWhitelist`, `UpdateMyWhitelist`,
`ToggleMyWhitelist`, `RemoveMyWhitelist` (com confirmação).

**Auditoria:** **sim, todas** — a whitelist decide **quem consegue falar com o
sistema**. Adicionar ou remover número é decisão de segurança:
`whitelist.adicionada`, `.alterada`, `.removida`, com o telefone **mascarado** na
descrição.

---

## E5 — Contatos completos e clientes (PJ)

- `UpdateMyContato` — editar nome, e-mail, tags. A lista já existe.
- `ListAtendimentosDoContato` — histórico (depende da timeline da N9d para o
  detalhe, mas a lista em si é independente).
- **Clientes PJ**: `ListMyClientes`, `CreateMyCliente`, `UpdateMyCliente`,
  `DesativarMyCliente`, `VincularContatoCliente`, `DesvincularContatoCliente`.
  O `ClienteRepository` está **completo e sem consumidor**
  (`clientes/clientes.rs`: `criar`, `buscar_por_id`, `adicionar_contato`,
  `remover_contato`, `listar_ativos`); as tabelas existem (migration 0004,
  incluindo o N:N `oraculo_cliente_contatos`).

Campos do `Cliente` na v1 (para a tela): nome fantasia, razão social, tipo,
CNPJ/CPF, telefone, site, ramo de atividade, observações e endereço completo
(CEP, logradouro, número, complemento...).

### Observabilidade & Auditoria

- **Auditoria:** `contato.alterado` e `cliente.criado`/`.alterado`/`.desativado`,
  com o **campo** alterado, não o valor. Cadastro de cliente é dado protegido.
- **Sanitização:** CNPJ/CPF, e-mail e endereço são PII — nunca em log.

---

## E6 — Perfil do contato (nome e foto)

Sincronizar via 🔌 `GetWhatsappProfilePicture` (`POST /user/avatar` — path real
do projeto; a pesquisa web **não** confirmou endpoint equivalente na API
clássica, mas o cliente do projeto já o implementa).

Estratégia: buscar sob demanda quando o contato não tem foto e a última
tentativa foi há mais de N dias (evitar bater na Evolution a cada abertura de
conversa). Guardar em `whatsapp_contact.foto_perfil` + origem.

Complementa o consumo do evento `CONTACTS` entregue na N8.5.5.

**Auditoria:** sem evento (enriquecimento derivado). **Log** com telefone
mascarado.

---

## E7 — E-mail transacional (a porta que não existe)

### O contexto

`grep -i "lettre|smtp|sendgrid" server/` → **zero**. Sem e-mail, três
funcionalidades da v1 não existem: convite entregue, ativação e **recuperação de
senha**. Hoje o convite é um link **relativo** exibido na tela para copiar.

### Decisão de arquitetura

**Porta plugável**, no mesmo padrão do pagamento (que já é porta com adaptador):
trait `EmailSender` em `application`, com dois adaptadores:

- **`BrevoSender`** (HTTP, via `reqwest` que já é dependência) — **default
  recomendado**: free tier de 300/dia permanente, primeiro plano pago barato,
  webhooks de entrega/bounce, sem SDK pesado. Ver comparativo em
  `ref_email_transacional.md`.
- **`SmtpSender`** (`lettre` 0.11.22, features `builder,tokio1,rustls,pool`) —
  para quem quiser servidor próprio. Doc na central:
  `doc_dev/libs/rust/lettre.md`.

Templates versionados no repositório (convite, ativação, recuperação), com o
`brand_name` do tenant e URL **absoluta** (fim do link relativo).

### Fora do código: DNS (bloqueia a entrega, não o build)

**SPF + DKIM são obrigatórios** desde 2026 (Google/Yahoo/Microsoft rejeitam sem).
DKIM leva **24–48 h** para propagar. DMARC entra depois, em fases
(`p=none` → `quarantine` → `reject`). **Iniciar o cadastro do domínio antes de
começar o código** — é o item de maior lead time da fase inteira.

### Observabilidade & Auditoria

- **Logs:** span `email.enviado` com `tipo` (convite/ativacao/recuperacao),
  `provedor`, `status`, `duracao_ms`. **Nunca o endereço completo** — mascarar
  (`j***@dominio.com`).
- **Auditoria:** **sim** — `email.enviado` e `email.falhou`, com tipo, destino
  mascarado e motivo. Convite e recuperação de senha são eventos de segurança
  (§08 4.2 já exige auditar convites).
- **Sanitização:** a chave de API do provedor em `SecretString`, vinda de
  `CoreSettings` cifrada; o **token** de recuperação **jamais** em log — nem no
  corpo do e-mail registrado.

---

## E8 — Recuperação de senha e reenvio de convite

Depende da E7.

- `SolicitarRedefinicaoSenha(email)` — **sempre responde sucesso**, exista o
  e-mail ou não (não vazar quais e-mails têm conta). Token de uso único, TTL
  curto (1 h), guardado com hash no Redis, invalidado no uso.
- `RedefinirSenha(token, nova_senha)` — valida força, revoga **todas** as sessões
  do usuário (a família de refresh tokens já suporta), e audita.
- `ReenviarConvite(invite_id)` — com rate limit por convite.
- Telas públicas `/recuperar-senha` e `/redefinir-senha/:token`.

### Observabilidade & Auditoria

- **Auditoria:** `auth.redefinicao_solicitada`, `auth.senha_redefinida`,
  `convite.reenviado` — todos com `ip_address` e `user_agent` do
  `RequestContext`. Eventos de segurança clássicos.
- **Sanitização:** token nunca em log, span, métrica ou auditoria. Rate limit
  por IP e por e-mail para não virar oráculo de enumeração.

---

## E9 — Residuais de operação

- Expor `ReprocessarDeadLetter` na borda (🔌, com escopo `operacional:admin`) +
  tela `/admin/dead-letter`.
- Registrar `LocalEngineFfiDataSource` no DI de produção (pendência N7.4).
- Job de expiração/aviso de assinatura (v1: `check_subscription_expirations` +
  `notify_expiring_subscriptions`) — agora possível com e-mail (E7).
- Capacidade do atendente (`max_conversas`) aplicada na elegibilidade.
- Normalizar `pollMessage`/`listMessage`/`buttonsMessage` (hoje caem em `Other`).
- CLI de export/import de `CoreSettings` no `control_plane` (backup de
  configuração; a v1 tinha 4 comandos).

---

## Sequência

```
E7 (e-mail) ──► inicia o DNS PRIMEIRO (24-48h de DKIM) ──► E8
E1 (sonda)  ──┐
E3 (detalhe) ─┼─► E2 (roteamento)  ← maior risco; exige E3 para vincular
E4 (whitelist)┘
E5 (contatos/PJ) ─── independente
E6 (perfil) ──────── independente, barato
E9 (residuais) ───── conforme sobra de ciclo
```

**Ordem recomendada:** começar o **DNS do e-mail** no dia 1 (lead time), e
executar E1 → E3 → E2 → E4 → E7 → E8 → E5 → E6 → E9.

## Riscos

| Risco | Mitigação |
|---|---|
| **E2 mandar conversa para a fila errada** | feature flag por tenant, fallback preservado, e2e com dois números, campo `origem_fluxo` no log |
| DKIM não propagar a tempo | iniciar no dia 1; a implementação não depende do DNS, só a entrega real |
| E-mail cair em spam | SPF+DKIM antes do primeiro envio; DMARC em fases; domínio próprio verificado |
| Sonda derrubar sessão saudável | histerese antes de reconectar; nunca reconectar no primeiro `unknown` |
| Recuperação de senha virar enumeração de e-mails | resposta idêntica sempre; rate limit por IP e por e-mail |
| Whitelist mal editada silenciar o tenant | confirmação na remoção + auditoria + aviso quando a lista fica vazia |

## Definition of Done

- [ ] Tenant com duas conexões roteia cada uma para o seu departamento.
- [ ] Conexão caída aparece no painel sem ninguém abrir a tela (E1 + N8.5.5).
- [ ] QR, bot, webhook, renomear e logout operáveis pela tela.
- [ ] Whitelist gerenciável, com auditoria e telefone mascarado.
- [ ] Convite chega por e-mail com URL absoluta; senha se recupera sozinha.
- [ ] Cliente PJ cadastrável e vinculável a contatos.
- [ ] Nenhum token, QR, chave de API ou PII em log/auditoria.
- [ ] Suítes verdes pelos scripts canônicos.
