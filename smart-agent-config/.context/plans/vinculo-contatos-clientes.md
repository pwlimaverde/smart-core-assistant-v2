---
type: plan
name: "Vínculo contato ↔ cliente, lista branca e campos do cadastro"
planSlug: vinculo-contatos-clientes
description: "Dar ao atendente e à IA a tarefa de vincular o contato WhatsApp a um cliente cadastrado: edição e vínculo manual no Kanban, vínculo automático coletando os dados do cliente na conversa, uma lista de contatos com tratamento próprio e a revisão dos campos do cadastro. Fecha as pendências C4 de painel-crm-e-campos-do-cartao e E4 de n11-operacao-cadastros, que estão com progresso 0."
summary: "V0 decide o significado de 'lista branca' e a política de vínculo automático; V1 editar e vincular no Kanban; V2 lista branca; V3 vínculo pela conversa; V4 campos do cadastro; V5 validação em CI e dev. Nada roda na máquina local."
status: draft
progress: 0
generated: "2026-10-17"
scaffoldVersion: "2.0.0"
---

# Vínculo contato ↔ cliente, lista branca e campos do cadastro

## Artefatos detalhados

- Plano completo reestruturado (fases com observabilidade e auditoria): `.context/plans/vinculo-contatos-clientes/plano_completo_vinculo-contatos-clientes.md`
- Documentação auxiliar (libs, serviços e pendências de verificação): `.context/plans/vinculo-contatos-clientes/info_aux_vinculo-contatos-clientes.md`

Status do workflow: scaffold, `workflow-init` e `plan link` pendentes, pois o MCP dotcontext está fora do ar.

## Diagnóstico (código, em 17/10/2026)

- **Vínculo já existe no banco e no app.** `oraculo_cliente` e `oraculo_contato` têm a tabela de junção com `UNIQUE (cliente_id, contato_id)`. O app tem `VincularContatoUsecase` (`clients/modulos/tenant_module/lib/src/features/clientes/`), mas a tela de clientes é a única que o usa.
- **O Kanban não edita o contato.** `operacional_module` não tem nenhuma chamada de atualização de contato nem de vínculo. A edição existe só em `tenant_module/features/contatos` (`AtualizarContatoUsecase`). Operador de atendimento não consegue corrigir o nome, o e-mail ou o cliente sem sair do Kanban.
- **"Lista branca" está invertida no código.** A tabela `whatsapp_whitelist` é uma lista de números a **IGNORAR** (diretoria, supervisão, testes). O webhook descarta o evento quando o remetente está nela (`server/apps/webhook_ingress/src/main.rs`, bloco 3, comentário explícito). Colocar um contato "na lista branca" hoje faz o sistema **parar de atender** esse número. A tela `ignorados_page.dart` usa o mesmo conceito com outro nome. Isso precisa ser decidido antes de qualquer tela nova (decisão D1).
- **A IA já devolve campos informados pelo cliente, mas o valor é descartado.** `ia_engine/src/ia_engine/domain/models.py` modela `CampoInformado` (campos que o cliente disse na mensagem). O plano `painel-crm-e-campos-do-cartao` registra o laço aberto: a IA pergunta, o cliente responde, o valor não volta ao cadastro, e a IA pergunta de novo.
- **Catálogo de campos.** O app tem CRUD de campos (`features/campos`, `CreateMyCampo`, `UpdateMyCampo`, `DesativarMyCampo`), mas o plano `painel-crm-e-campos-do-cartao` registra que o catálogo está somente-leitura em produção, o que impede o tenant de criar os seus. Os campos do contato (nome, telefone, e-mail, observações) e do cliente (CNPJ/CPF, endereço, site, ramo) estão no banco; falta confirmar com você quais estão faltando.
- **Planos sobrepostos.** `painel-crm-e-campos-do-cartao` (C4), `n11-operacao-cadastros` (E4, whitelist) e `regras-do-bot-e-permissoes` tratam de partes disto, todos com progresso 0. Este plano consolida o que é específico de vínculo, lista e campos, e remete aos demais para o resto.

## Decisões pendentes (dono do produto)

**D1. O que é "lista branca"?**
- (a) **Não atender:** manter o comportamento atual, só renomear na tela ("Ignorar este número") e adicionar o botão no Kanban. Mudança pequena.
- (b) **Atendimento prioritário / permitido:** contatos que o bot pode responder mesmo fora do horário, ou que sempre vão para um atendente. Exige nova regra no webhook e no roteamento. Mudança média.
- Recomendação: (a) agora, porque o código já tem o mecanismo; (b) só se você confirmar que é o que precisa.

**D2. O vínculo automático cria cliente sozinho ou só sugere?**
- (a) A IA **sugere** o cliente (por CPF/CNPJ ou telefone) e o atendente confirma com um clique.
- (b) A IA **cria e vincula** sem confirmação.
- Recomendação: (a). CPF e CNPJ vindos de conversa são dados que a IA pode errar, e a LGPD exige que o titular/operador saiba o que foi gravado. (b) fica como opção depois de medir a taxa de acerto.

**D3. Quais campos estão incompletos?** Preciso da lista do que você espera no cadastro de contato e de cliente. Sem ela, a fase V4 fica com o inventário do que o código tem, não do que o negócio precisa.

## Fases

### V0 — Decisões (antes de codificar)
- [ ] Responder D1, D2 e D3.
- [ ] Confirmar se o catálogo de campos deve estar liberado para todos os tenants em produção (hoje somente-leitura, conforme `painel-crm-e-campos-do-cartao`).

### V1 — Editar e vincular no Kanban (manual)
Objetivo: o atendente corrige o contato e vincula o cliente sem sair do atendimento.

- [ ] `operacional_module`: na ficha do contato (`painel_ficha.dart`), botão **Editar contato** (nome, e-mail, observações; telefone só leitura) e seção **Cliente** (vinculado ou "Vincular a cliente").
- [ ] **Vincular:** busca de cliente por nome, CPF/CNPJ ou telefone, com opção de criar cliente novo na mesma tela (reaproveitar `VincularContatoUsecase`).
- [ ] Desvincular, com confirmação.
- [ ] Os casos de uso vêm de `tenant_module` (contatos e clientes). Antes de codificar, verificar a regra de dependência entre módulos: se `operacional_module` não pode importar `tenant_module`, mover os casos de uso para o `core_module` ou expor um gateway compartilhado.
- [ ] Auditoria: cada edição e vínculo grava em `auditoria` (quem, quando, o que mudou).

### V2 — Lista branca (conforme D1)
- Se D1 = (a): renomear o rótulo de `ignorados_page.dart` para "Não atender", adicionar botão **Não atender este número** na ficha do contato (usa `CriarIgnoradoParameters`, já existente) e manter o registro na auditoria.
- Se D1 = (b): nova coluna ou tabela de permissão, gate no `webhook_ingress` antes do roteamento, tela de gestão e RPCs novos em `admin.proto` (regenerar o contrato sem `map<>`, ver memória `proto-sem-map`).

### V3 — Vínculo automático pela conversa (conforme D2)
Objetivo: a IA coleta os dados do cliente na conversa e propõe o cadastro.

- [ ] **Fechar o laço aberto:** o valor de `CampoInformado` deve ser gravado (hoje é descartado). Ponto de partida: `ia_engine/domain/models.py` e o caminho de volta no `worker`.
- [ ] **Extração:** a IA devolve, para cada campo do catálogo, o valor, a confiança e a frase do cliente que originou o valor. Valor sem frase de origem não é gravado.
- [ ] **Validação em código, não na IA:** CPF e CNPJ com dígito verificador, e-mail com formato válido. Campo inválido vira pergunta de volta ao cliente, não gravação.
- [ ] **Sugestão de vínculo:** ao identificar CPF/CNPJ ou telefone de um cliente existente, o Kanban mostra "Vincular a [cliente]?" para o atendente confirmar (D2 = a).
- [ ] **Sem cliente existente:** o atendente vê "Criar cliente com estes dados?", já preenchido.
- [ ] **Limite de escrita pela IA:** a IA nunca altera um vínculo que já existe. Só propõe.
- [ ] Teste com respostas gravadas (sem chamar a LLM na CI), cobrindo: CPF válido, CPF inválido, cliente sem frase de origem, e conflito com um vínculo existente.

### V4 — Campos do cadastro
- [ ] Inventário: listar o que existe em `oraculo_contato` e `oraculo_cliente` e marcar o que o app edita e o que só o banco tem.
- [ ] Definir o conjunto mínimo por tipo (contato, cliente PF, cliente PJ) conforme a resposta à D3.
- [ ] Liberar o CRUD do catálogo de campos para o tenant (ver a decisão em V0), com os campos padrão criados no cadastro do tenant.
- [ ] Campos obrigatórios por tipo de cliente, com validação no servidor.

### V5 — Validação e entrega
- [ ] `dart analyze` e `cargo fmt` locais; testes só na CI (regra do projeto).
- [ ] CI verde, incluindo o teste de widget da ficha e os testes Rust de vínculo.
- [ ] Ensaio na dev: vincular manualmente, editar contato, colocar um número em "Não atender", conversar com a IA e conferir a sugestão de vínculo.
- [ ] Checklist de aceite (abaixo) conferido pelo dono do produto.

## Riscos

- **Dados pessoais pela IA (CPF, CNPJ, endereço):** a extração precisa de validação e de auditoria; sem isso, não entra em produção.
- **Inversão do termo "lista branca":** se D1 não for decidida, uma tela nova pode fazer o sistema parar de atender um cliente. Por isso V2 só começa depois de D1.
- **Dependência entre módulos:** a ficha do Kanban precisa de casos de uso que hoje estão no `tenant_module`.
- **Contrato gRPC:** novos campos do `admin.proto` exigem regenerar o contrato com o `protoc_plugin` 23 (ver memória e o commit `4fb297aa`).

## Critérios de aceite

- Um atendente edita o contato e vincula um cliente, sem sair do Kanban, em menos de um minuto.
- Um número marcado como "Não atender" não recebe resposta do bot (ou o rótulo e o efeito correspondem à decisão D1).
- A IA sugere vínculo a partir de CPF/CNPJ dito na conversa, e nunca grava um dado inválido.
- Toda edição de contato, vínculo e número ignorado aparece na auditoria.
- O catálogo de campos é editável pelo tenant, e o conjunto mínimo por tipo está definido.

## Relação com os outros planos

- `painel-crm-e-campos-do-cartao` (C4 e o laço da IA): este plano assume o C4 e o laço aberto de V3.
- `n11-operacao-cadastros` (E4, whitelist): V2 assume a whitelist, com a semântica corrigida por D1.
- `regras-do-bot-e-permissoes`: a lista branca de V2 depende da decisão de permissões desse plano se D1 = (b).
