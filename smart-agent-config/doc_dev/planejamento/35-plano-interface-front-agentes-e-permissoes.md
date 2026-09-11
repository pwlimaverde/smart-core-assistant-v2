# 35 — Plano: interface do front para agentes de IA e o novo modelo de permissões

> **Origem:** a fase **N13** (servidor MCP, plano `.context/plans/n13-mcp-agentes.md`)
> entregou backend completo e **uma** tela; e a **D4** da fase
> `regras-do-bot-e-permissoes`, que chegou pela `dev`, criou um papel
> somente-leitura que o painel não sabe representar.
>
> **Este plano é só o delta de interface.** O que o backend já faz e a tela não
> mostra, e o que a tela mostra de um jeito que contradiz o backend.

---

## Como este documento nasceu

Ao mesclar a N13 com a `dev` (2026-09-10), duas coisas apareceram que nenhum dos
dois planos previa. Nenhuma é bug de código — são lacunas de **interface** que só
ficam visíveis quando os dois lados existem ao mesmo tempo:

1. O Definition of Done da N13 diz: *"`QueryAuditLog` responde 'o que o agente do
   fulano fez ontem' com um único filtro."* Ele **não é satisfazível hoje**:
   `query_audit_log` exige `exigir_superuser_do_metadata`
   (`grpc_web.rs:4397`), e `QueryAuditLogRequest` tem quatro campos —
   `tenant_id`, `event_type`, `limit`, `offset` — nenhum deles de origem. O dono
   do negócio não tem como ver o que o agente dele fez, e nem o superusuário
   consegue filtrar "só o que veio de agente" com um filtro.
2. A D4 introduziu `escopos_somente_leitura()` — o papel `viewer` da v1, que a v2
   não sabia representar. Um usuário com apenas `atendimentos:read` entra no
   painel e vê **dois** itens de menu: Kanban e Aplicativos conectados. Todo o
   resto está atrás de `if (isTenantAdmin)`
   (`tenant_drawer.dart:57`), que é binário. O papel existe no backend e não
   existe na tela.

---

## O que este plano resolve

| Bloco | Entrega | Por que existe |
|---|---|---|
| **F1** | "O que o agente fez" — auditoria do próprio tenant | Fecha um DoD da N13 que hoje está aberto. É a única forma de o dono confiar no agente |
| **F2** | Menu por escopo, não por `isTenantAdmin` | O papel somente-leitura da D4 existe no backend e não na tela |
| **F3** | Tela de consentimento com a identidade visual do produto | É a única superfície do produto que não parece com ele — e é justamente a que pede a senha |
| **F4** | Ajustar permissões de um agente sem desconectar | Hoje a única saída é desconectar e reconectar |
| **F5** | Descoberta: ninguém sabe que o recurso existe | Um recurso que precisa ser explicado por fora não foi entregue |

**F1 é o de maior valor**, e por um motivo que não é técnico: um agente de IA que
age sozinho na conta de alguém só é aceitável se essa pessoa puder **auditar** o
que ele fez. Sem F1, a resposta para "o que esse robô andou fazendo?" é "abra um
ticket com o suporte". F2 é o de maior risco de regressão.

---

## F1 — "O que o agente fez": auditoria do próprio tenant

### O defeito

Toda ação de agente já é auditada. A N13 fez o `mcp_server` mandar
`user-agent: SmartCoreAssistant-MCP/<tool>` no metadata gRPC, o `runtime_api`
copia isso para o campo `user_agent` do envelope, e o `data_postgres` grava no
`audit_log`. **O dado existe.** O que não existe é caminho para ele chegar a
quem tem interesse nele:

* `query_audit_log` exige superusuário;
* o filtro não tem campo de origem;
* o painel do tenant não tem tela de auditoria nenhuma — a única existe no
  `admin_module` (`features/audit/presentation/pages/audit_page.dart`).

### Contrato (aditivo)

Duas mudanças, as duas aditivas:

```proto
// Auditoria do PRÓPRIO tenant. Distinta de QueryAuditLog, que é do
// superusuário e cross-tenant: aqui o tenant vem das claims, nunca do request,
// e não existe parâmetro que alcance outro tenant.
message ListMyAuditLogRequest {
  // Filtro de origem. Vazio = tudo. O caso que motivou o campo é "mcp":
  // é ele que responde "o que o agente fez" com UM filtro.
  string origem = 1;      // "" | "mcp" | "painel"
  // Restringe a um aplicativo conectado específico (o `id` de McpGrantItem).
  string grant_id = 2;
  string event_type = 3;
  int64 desde = 4;        // timestamp_millis
  int32 limit = 5;        // teto de 200 no servidor
  int32 offset = 6;
}

message MyAuditLogEntry {
  int64 timestamp = 1;
  string event_type = 2;
  string message = 3;
  // "mcp" | "painel" — derivada do user_agent, não um campo novo na tabela.
  string origem = 4;
  // Nome do aplicativo, quando a origem é mcp. Vem do grant, é TEXTO DE
  // TERCEIRO: escapar na renderização.
  string client_name = 5;
  string tool = 6;        // nome da tool, quando aplicável
  int32 user_id = 7;
  string user_nome = 8;
}
```

**Onde a `origem` é derivada, e por quê:** no `data_postgres`, a partir do
prefixo de `user_agent`. Não há coluna nova. A alternativa — acrescentar
`origem` ao `audit_log` — exigiria migration, backfill e manter dois campos
dizendo a mesma coisa; e o `user_agent` já é gravado desde N13 exatamente para
isso.

**Escopo exigido:** `SOMENTE_ADMIN` no `rbac::MAPA`. A trilha de auditoria do
negócio inteiro é dado sensível — um `staff` não deve ler o que os colegas
fizeram. **Exceção deliberada:** quando `grant_id` referencia um grant **do
próprio usuário**, qualquer sessão autenticada pode ler. É o mesmo princípio da
tela de Aplicativos conectados: o agente é meu, o rastro dele é meu.

### UI

Uma **aba dentro de Aplicativos conectados**, não uma tela nova no menu. O
raciocínio: a pergunta "o que o agente fez" nasce olhando a lista de agentes, e
um item de menu a mais num drawer que já tem onze é custo sem retorno.

```
Aplicativos conectados
├── [Conectados]   ← a lista de hoje
└── [Atividade]    ← F1
```

A aba **Atividade** mostra, do mais recente para o mais antigo: quando, qual
aplicativo, qual operação em linguagem de negócio ("enviou mensagem no
atendimento 412", não `mensagem.enviada`), e quem autorizou. Filtros: aplicativo
e período.

**O que NÃO aparece:** conteúdo de mensagem, telefone, nome de contato. O
`audit_log` não os guarda (a N13 proibiu), e a tela não deve inventar um jeito de
mostrar o que o backend se recusou a registrar.

### DoD

- [ ] Um `tenant:admin` vê, em uma tela, tudo que os agentes fizeram no negócio.
- [ ] Um `staff` vê a atividade **dos próprios** agentes e de nenhum outro.
- [ ] O filtro "só agentes" é **um** controle, não uma busca por texto.
- [ ] Teste de widget: lista vazia diz que nenhum agente agiu ainda, sem parecer erro.
- [ ] Nenhuma entrada exibe PII — teste sobre uma fixture que tenta injetá-la.

---

## F2 — Menu por escopo, não por `isTenantAdmin`

### O defeito

`tenant_drawer.dart:57` é um `if (isTenantAdmin)` que envolve **nove** dos onze
itens. Consequências concretas:

| Papel (D4) | Escopos | O que o menu mostra hoje |
|---|---|---|
| `admin` | `tenant:admin` | tudo |
| `manager` | leitura + escrita, sem `configuracoes:write` | **Kanban e Aplicativos conectados** |
| `staff` | `clientes:read`, `atendimentos:*` | **Kanban e Aplicativos conectados** |
| `viewer` (novo na D4) | `atendimentos:read` | **Kanban e Aplicativos conectados** |

Um `manager` que a N13.3 acabou de autorizar a editar fluxos **não vê o item de
menu de fluxos**. O backend passou a aceitar, a tela continua escondendo. É o
espelho exato do defeito que a N13.3 corrigiu no servidor — e enquanto ele
existir, metade do valor da N13.3 fica invisível.

### A correção

Trocar o booleano por uma consulta de escopo, com a **mesma** regra do
`rbac::MAPA` do servidor:

```dart
/// Espelho do `rbac::MAPA` do runtime_api, do lado da tela.
///
/// Não é a barreira — a barreira é o servidor, que recusa a chamada. Isto evita
/// oferecer à pessoa um caminho que vai terminar em "sem permissão", que é a
/// pior forma de comunicar uma restrição.
const _escopoPorRota = <String, List<String>>{
  '/tenant/painel':      ['atendimentos:read'],
  '/tenant/contatos':    ['clientes:read'],
  '/tenant/equipe':      ['operacional:read'],
  '/tenant/fluxos':      ['atendimentos:read'],
  '/tenant/conexoes':    ['operacional:read'],
  '/tenant/treinamento': ['treinamento:read'],
  '/tenant/convites':    [],   // só admin
  '/tenant/usuarios':    [],   // só admin
  '/tenant/config':      ['configuracoes:read'],
  '/tenant/integracoes': null, // qualquer sessão: o recurso é do usuário
};
```

**Lista vazia = só admin**, exatamente como no servidor — e com a mesma
armadilha de leitura, então o nome importa: use uma constante `somenteAdmin`, não
`[]` solto.

### O risco desta mudança, e como conter

É o bloco de maior risco do plano: hoje o menu é restritivo demais, e
liberá-lo pode expor uma tela que **falha** ao abrir por depender de uma chamada
que o servidor recusa. Antes de ligar, é preciso cruzar cada tela com o escopo
que suas chamadas exigem — não com o escopo da rota de menu.

Passo obrigatório: para cada uma das nove telas, listar as RPCs que ela chama na
montagem e confirmar que o escopo do menu é **subconjunto** do escopo de todas
elas. Onde não for, a tela precisa degradar (esconder o botão de ação) em vez de
falhar.

### DoD

- [ ] Um `manager` vê e usa a tela de fluxos.
- [ ] Um `viewer` vê as telas de leitura e **nenhum** botão que escreve.
- [ ] Nenhuma tela do menu falha ao abrir para o papel que a vê.
- [ ] O guard global (`tenantAuthRedirectTarget`) concorda com o menu: nada
      visível leva a um redirect.
- [ ] Teste de widget por papel, com os quatro conjuntos de escopo da tabela.

---

## F3 — A tela de consentimento precisa parecer com o produto

### A situação

A tela de login e a de consentimento do OAuth são **HTML servido pelo Rust**
(`server/apps/control_plane/src/oauth/html.rs`), com CSS embutido. Funcionam e
são seguras — CSP `script-src 'none'`, escape próprio, teste provando que o nome
do cliente não vira script. Mas são a única superfície do produto que não parece
com ele. E é justamente a tela que pede a senha.

Isso importa mais do que estética: uma tela de autorização que não parece com o
serviço é indistinguível de uma tela de phishing. O usuário é treinado a
desconfiar — e aqui nós queremos que ele confie, porque a tela é nossa.

### O que **não** fazer

**Não transformar em rota Flutter.** A tela de consentimento tem de ser
renderizada pelo authorization server, no domínio dele. Servi-la de um SPA
acrescentaria um intermediário entre a senha e quem a valida, e tornaria
possível a um bundle comprometido capturar credencial — que é exatamente o que o
desenho do OAuth existe para evitar. O CSP `script-src 'none'` é feature, não
limitação.

### O que fazer

1. Extrair do `design_system_module` os **tokens** (paleta, tipografia, raio de
   borda, espaçamento) para um CSS único servido pelo AS. Tokens, não
   componentes: o objetivo é parecer com o produto, não reimplementá-lo.
2. Logotipo, servido pelo próprio AS (não por CDN nem por outro domínio — o CSP
   é `default-src 'none'`, e afrouxá-lo por um logo seria mau negócio).
3. Manter o texto como está. Ele foi escrito para ser lido por quem está
   decidindo, e as três informações obrigatórias por spec — nome do cliente,
   hostname do retorno, aviso de só-localhost — já estão lá.
4. Revisar em tela pequena: o fluxo do Claude mobile abre esta página num
   navegador de celular.

### DoD

- [ ] Alguém que usa o painel reconhece a tela como sendo do mesmo produto.
- [ ] O CSP continua `default-src 'none'; script-src 'none'`.
- [ ] Os testes de escape do `html.rs` continuam passando sem alteração.
- [ ] Legível em 360 px de largura.

---

## F4 — Ajustar permissões sem desconectar

### O defeito

A tela lista os escopos concedidos e não permite mexer. Para tirar uma permissão
de um agente, o caminho é desconectar e reconectar — e reconectar exige voltar ao
cliente de IA, achar o conector, remover, adicionar de novo. Na prática, ninguém
reduz permissão: ou aceita o que concedeu, ou desiste do agente.

### A correção

Um botão **Ajustar permissões** que leva ao fluxo de consentimento já existente,
com o `client_id` e o `redirect_uri` do grant atual pré-preenchidos e as caixas
marcadas conforme o que está concedido hoje. O AS já trata reconsentimento:
`registrar_consentimento` revoga o grant anterior do mesmo par (usuário, cliente)
antes de gravar o novo, então o resultado é substituição, não acúmulo.

**O que isto exige do backend:** nada. O fluxo existe. Falta a UI oferecê-lo — um
link para `/oauth/authorize` com os parâmetros do grant.

**O que isto exige de honestidade na tela:** depois de ajustar, o agente precisa
renovar o token para sentir a mudança, e isso leva até 15 minutos. O mesmo aviso
da revogação, pelo mesmo motivo.

### DoD

- [ ] Reduzir escopo não exige tocar no cliente de IA.
- [ ] A tela diz que a mudança vale na renovação seguinte, com o número real.
- [ ] Ampliar escopo passa pela tela de consentimento — nunca em silêncio.

---

## F5 — Descoberta

### O defeito

O recurso só é encontrado por quem já sabe que ele existe. Não há nada no painel
que diga "você pode ligar um assistente de IA à sua conta".

### A correção

Três pontos, em ordem de custo:

1. **Estado vazio da própria tela** (já existe, e está bom): explica o que fazer.
   Falta chegar nele.
2. **Cartão dispensável no Painel**, para quem tem zero agentes conectados: uma
   linha do que o recurso faz e um botão que leva à tela. Dispensável de
   verdade — com `dispensado` guardado por usuário, não por tenant, porque a
   conexão é pessoal.
3. **Link no fim da tela de Configuração**, onde quem está configurando o negócio
   já está olhando.

### O que **não** fazer

Nenhum modal de boas-vindas, nenhum tour. O recurso é útil para quem tem uma
tarefa; interromper quem tem outra não o torna mais descoberto, só mais irritante.

### DoD

- [ ] Um usuário que nunca ouviu falar de MCP chega à tela sem ser instruído.
- [ ] O cartão do painel, dispensado, não volta.
- [ ] Quem já tem agente conectado nunca vê o cartão.

---

## Ordem e dependências

```
F2 (menu por escopo) ──┐
                       ├──▶ F1 (auditoria) ──▶ F5 (descoberta)
F3 (visual do consent) ┘
F4 (ajustar permissões) — independente, pode entrar a qualquer momento
```

**F2 antes de F1** por um motivo prático: a aba de Atividade vive dentro de
Aplicativos conectados, e F2 é o que faz as telas aparecerem para quem não é
admin. Entregar F1 primeiro deixaria a auditoria visível só para admin, que é
menos da metade do público dela.

**F3 é independente e paralelizável** — é o único bloco que não toca Flutter.

**Primeiro corte utilizável:** F2 + F1. Com os dois, o novo modelo de permissões
aparece na tela e o agente passa a ser auditável por quem o autorizou. F3, F4 e
F5 melhoram um recurso que já funciona.

---

## Riscos

| Risco | Impacto | Mitigação |
|---|---|---|
| **F2 expõe tela que falha ao abrir** | Usuário vê erro onde antes via nada — pior que a restrição | Passo obrigatório de cruzar cada tela com o escopo das RPCs que ela chama na montagem; degradar escondendo ação, nunca falhando |
| **F2 contradiz o guard global de rota** | Item visível que redireciona ao clicar | `tenantAuthRedirectTarget` e o mapa do menu saem da mesma fonte |
| **`client_name` do CIMD na tela de auditoria** | XSS / spoofing | É texto de terceiro: escapar, limitar tamanho, e mostrar sempre junto do host — a mesma regra da tela de Aplicativos conectados |
| **F1 vaza trilha entre usuários** | Um `staff` lendo o que o colega fez | O `grant_id` é validado contra o dono; sem ele, exige `tenant:admin`. Teste de isolamento entre dois usuários do mesmo tenant |
| **F3 afrouxa o CSP para carregar fonte ou logo de fora** | Superfície de script na tela que pede senha | Servir tudo do próprio AS; o CSP não muda |
| **Mapa de escopo do menu divergir do `rbac::MAPA`** | Menu promete o que o servidor nega | Teste que lê o `rbac.rs` e compara, no molde do `test_catalogo_de_escopos.py` do `mcp_server` |

---

## O que este plano NÃO cobre

* **Elicitation (confirmação nível 1 do MCP).** É protocolo entre servidor e
  cliente de IA; a tela do painel não participa. Fica na N13.6.
* **Tela de superusuário para agentes de todos os tenants.** Só faz sentido
  depois de haver agentes em uso; hoje seria projetar no vazio.
* **Aplicativo móvel.** O `tenant_module` é Flutter Web; nada aqui depende de
  mobile, e a tela de consentimento abre no navegador do celular por conta do
  fluxo OAuth, não do nosso app.
* **A conversa no painel e o catálogo de campos** — são N9 E12 e E13, e o
  [doc 34](./34-plano-painel-crm-e-campos-do-cartao.md) já os precisou.

---

*Aterrado em `grpc_web.rs:4397` (`query_audit_log` exige superusuário),
`QueryAuditLogRequest` (quatro campos, nenhum de origem), `tenant_drawer.dart:57`
(`if (isTenantAdmin)` envolvendo nove itens), `login.rs::escopos_somente_leitura`
(o papel `viewer` da D4), `oauth/html.rs` (as duas telas servidas pelo Rust) e
`rbac.rs::MAPA` (43 rotas com escopo declarado). Leitura de 2026-09-11.*
