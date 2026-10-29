# Plano Completo — Vínculo contato ↔ cliente, lista branca e campos do cadastro

> Reestruturado em 17/10/2026 a partir de `.context/plans/vinculo-contatos-clientes.md`.
> Documentação auxiliar: `info_aux_vinculo-contatos-clientes.md`.
> Decisões pendentes (D1, D2, D3) continuam com o dono do produto. Nenhuma fase de código começa antes da V0.

## Correções aplicadas nesta reestruturação

| # | Antes | Depois | Motivo / fonte |
|---|---|---|---|
| C1 | "Lista branca" tratada como permissão de atendimento | Termo passa a ser "**Não atender**" até D1 ser decidida. O código atual (`webhook_ingress`, bloco 3) já trata a whitelist como lista de números a ignorar | `server/apps/webhook_ingress/src/main.rs`, comentário do bloco 3 |
| C2 | Vínculo automático sem regra de auditoria | Cada vínculo sugerido e cada dado alterado pela IA gera registro com `message_id` de origem | `08_diretrizes_seguranca.md` §4.2 (acesso e alteração de dado protegido) |
| C3 | Campos do cadastro sem critério de validação | Validação de CPF/CNPJ (dígito verificador) e e-mail no código; IA nunca grava dado inválido | Regra do plano V3; a IA extrai, o código valida |
| C4 | Sem referência ao estado da documentação | Verificação de libs marcada como pendência antes de V3 | Central `doc_dev/libs/` ausente; Context7 sem autenticação |
| C5 | Fases sem observabilidade | Cada fase ganha "Observabilidade & Auditoria" com os três eixos | Requisito transversal da skill `plan-restructuring` |

## Decisões registradas

- **D1 = (a) não atender.** "Lista branca" significa lista de números que o sistema não atende. Sem atendimento permitido por número.
- **D2 = (a) a IA sugere, o atendente confirma.** A IA nunca cria nem altera vínculo sozinha.
- **D3 = em aberto para o contato.** Achado: o schema do contato e do cliente na v2 já tem todos os campos da v1 (ver abaixo). A lacuna é de exposição na interface, não de colunas.

## Achados de campos (v1 `old/` × v2 schema)

**Contato (`oraculo_contato`)**
- v1 (`app/clientes/models.py`): telefone, nome_contato, slug, email, nome_perfil_whatsapp, data_cadastro, ultima_interacao, ativo, metadados, foto_perfil, foto_perfil_url_origem.
- v2: as mesmas colunas, mais `foto_verificada_em` (0039) e `excluido_em`/`excluido_por_id` (0045).
- Na v2, o diálogo de contato (`dialogo_contato.dart`) edita só Telefone, Nome e E-mail. O nome do perfil do WhatsApp não aparece, e a ficha do Kanban não tem edição.

**Cliente (`oraculo_cliente`)**
- v1: nome_fantasia, slug, razao_social, tipo (PF/PJ), cnpj, cpf, telefone, site, ramo_atividade, observacoes, cep, logradouro, numero, complemento, bairro, cidade, uf, pais, contatos (M:N), data_cadastro, ultima_atualizacao, ativo, metadados.
- v2 (`0004`): as mesmas colunas, com `site` como VARCHAR(200) em vez de URL validada; M:N em `oraculo_cliente_contatos`; exclusão lógica (0045).
- A v1 validava CPF, CNPJ, CEP e telefone no modelo (dígito verificador não era validado, só tamanho e sequência zero). A v2 precisa ter essas validações no servidor (C3 do plano).

**Conclusão para D3:** não há coluna faltando em relação à v1. O que falta é:
1. Interface: editar contato no Kanban (V1).
2. Campos que a operação precisa e a v1 não tinha: nenhum identificado. Confirmar com você quais são (D3 pendente).
3. Validação de CPF/CNPJ com dígito verificador (a v1 não tinha; é melhoria).

## Fases

### V0 — Decisões (bloqueia tudo)

**Entregas**
- D1 e D2 registrados acima.
- D3: confirmar quais campos novos você quer além dos da v1.
- Confirmar liberação do catálogo de campos para todos os tenants em produção.

**Observabilidade & Auditoria**
- Logs: nenhum (fase documental).
- Auditoria: a decisão D2 e a liberação do catálogo ficam registradas no histórico do plano, não no `audit_log`.
- Sanitização: não se aplica.

### V1 — Editar e vincular no Kanban (manual)

**Escopo**
- Ficha do atendimento (`clients/modulos/operacional_module/.../widgets/painel_ficha.dart`), com edição direta sem sair da conversa:
  - **Contato:** nome, e-mail, cargo, segmento e observações; telefone só leitura; nome do perfil do WhatsApp exibido.
  - **Cliente:** nome fantasia, razão social, PF/PJ, CPF, CNPJ, telefone, site, segmento, cargo do responsável, endereço, observações.
  - Botão de editar ao lado de cada seção, sem trocar de tela. Salvar aplica no mesmo lugar onde o atendente está.
- Critério de fácil acesso: a ficha do atendimento abre a partir do cartão do Kanban e da conversa, com um toque.
- Seção **Cliente**: vinculado ou "Vincular a cliente".
- Vincular: busca de cliente por nome, CPF/CNPJ ou telefone; criar cliente na mesma tela.
- Desvincular, com confirmação.
- Casos de uso já existentes: `AtualizarContatoUsecase` (`tenant_module/features/contatos`) e `VincularContatoUsecase` (`tenant_module/features/clientes`). Verificar a regra de dependência entre módulos antes de codificar: se `operacional_module` não pode importar `tenant_module`, mover os casos de uso para `core_module` ou expor um gateway compartilhado.

**Servidor**
- Reusar `AtualizarContato` e o vínculo existente (`oraculo_cliente` ↔ `oraculo_contato`, `UNIQUE (cliente_id, contato_id)`).

**Observabilidade & Auditoria**
- *Logs/trace:* span `contato.editar` e `contato.vincular` com `tenant_id`, `contato_id`, `cliente_id` e `error_code`. Erro de validação não é erro de infra: sem `#[instrument(err)]`.
- *Auditoria (`audit_log`):* `contato.editado` (nomes dos campos alterados, sem valores), `contato.vinculado_cliente` e `contato.desvinculado_cliente` (com `user_id` do `RequestContext`, `ip_address`, `user_agent`, `event_type`, descrição sem CPF/CNPJ). Publicação assíncrona pelo `transport::bus`.
- *Sanitização:* telefone mascarado em log. CPF/CNPJ e e-mail nunca em log. Nenhum campo novo em mensagem de erro gRPC.

**Critério de aceite:** atendente edita e vincula sem sair do Kanban; cada ação aparece no `audit_log`.

### V2 — Não atender (conforme D1)

**Se D1 = (a) não atender**
- Renomear o rótulo de `ignorados_page.dart` para "Não atender".
- Botão **Não atender este número** na ficha do contato, usando `CriarIgnoradoParameters` (já existente).
- Servidor: sem mudança de semântica (o `webhook_ingress` já descarta).

**Se D1 = (b) atendimento permitido**
- Nova regra no `webhook_ingress`, antes do roteamento, com a decisão de permissões do plano `regras-do-bot-e-permissoes`.
- Nova coluna ou tabela, RPCs em `admin.proto` (regenerar contrato sem `map<>`, ver memória `proto-sem-map`), tela de gestão.

**Observabilidade & Auditoria**
- *Auditoria:* `whitelist.adicionada` e `whitelist.removida` com telefone mascarado (padrão já definido no plano `n11-operacao-cadastros`).
- *Logs:* `webhook.ignored` já existe; manter sem o número completo.
- *Sanitização:* telefone mascarado.

**Critério de aceite:** número marcado não recebe resposta do bot, e a alteração aparece na auditoria.

### V3 — Vínculo automático pela conversa (conforme D2)

**Escopo**
- Fechar o laço aberto: o valor de `CampoInformado` (em `ia_engine/src/ia_engine/domain/models.py`) passa a ser gravado no cadastro. Hoje é descartado (plano `painel-crm-e-campos-do-cartao`).
- Extração pela LLM com saída tipada (pydantic): para cada campo do catálogo, valor, confiança e frase do cliente que originou o valor. Valor sem frase de origem não é gravado.
- Validação **em código**: CPF/CNPJ com dígito verificador, e-mail com formato válido. Campo inválido vira pergunta de volta ao cliente.
- Sugestão de vínculo por CPF/CNPJ ou telefone: o Kanban mostra "Vincular a [cliente]?" (D2 = a). Sem cliente existente: "Criar cliente com estes dados?", já preenchido.
- A IA nunca altera um vínculo existente; só propõe.

**Servidor**
- Worker: consumir o resultado da extração e gravar no cadastro, com a validação.
- Contrato gRPC: campos novos de sugestão e de origem. Regenerar com `protoc_plugin` 23 (ver commit `4fb297aa`).

**Observabilidade & Auditoria**
- *Logs/trace:* span `ia.extrair_campos` com `tenant_id`, `atendimento_id`, quantidade de campos extraídos, quantidade de rejeitados pela validação e `error_code`. **Nunca** o valor extraído nem a frase do cliente.
- *Auditoria:* `cliente.dado_alterado_ia` com nome do campo, `message_id` de origem e `event_type`. O valor vai no registro do dado, não em log. `contato.vinculo_sugerido_ia` quando a IA sugere; `contato.vinculado_cliente` com origem `atendente` quando confirmado.
- *Sanitização:* CPF/CNPJ com `secrecy::SecretString` no caminho Rust; no Python, mascarar antes de qualquer log. Teste garante que nenhum log contém o valor.

**Pendência de verificação:** API atual de `pydantic` 2.12 (ver `info_aux`).

**Testes**
- Respostas gravadas (sem chamar a LLM na CI): CPF válido, CPF inválido, campo sem frase de origem, conflito com vínculo existente.

**Critério de aceite:** a IA sugere o cliente a partir de CPF/CNPJ dito na conversa; dado inválido nunca é gravado; nenhum log contém o valor.

### V4 — Campos do cadastro

**Escopo**
- Inventário: o que existe em `oraculo_contato` e `oraculo_cliente`, e o que o app edita (ver "Achados de campos").
- Campos novos solicitados pelo operador:
  - **Contato:** `cargo` (VARCHAR 100), `segmento` (VARCHAR 100), `observacoes` (TEXT). Hoje o contato só tem `metadados` JSONB, sem campo de observação próprio.
  - **Cliente:** `cargo_responsavel` (VARCHAR 100), `observacoes` já existe (TEXT). `segmento` reaproveita `ramo_atividade` (VARCHAR 200), evitando duplicar o mesmo dado; a interface mostra o rótulo "Segmento".
- Migração nova em `infrastructure_postgres/migrations` com `ADD COLUMN IF NOT EXISTS`, sem alterar as existentes. Colunas nullable, sem default que quebre cadastro antigo.
- Campos disponíveis no app Windows (tela de atendimento, ficha de contato e de cliente) e no endpoint gRPC (contrato regenerado, ver V2 sobre `admin.proto`).
- Conjunto mínimo obrigatório: nenhum campo novo é obrigatório. Só nome do contato segue opcional (já é) e nome fantasia do cliente segue obrigatório (já é).
- Catálogo de campos: **já liberado.** A tela "Campos do atendimento" aparece no menu do tenant (`tenant_drawer.dart`) para quem tem escopo `configuracoes`; a escrita exige `configuracoes:write` (`permissoes_de_tela.dart`). Nenhuma mudança de permissão é necessária.
- Campos obrigatórios por tipo de cliente, com validação no servidor.

**Observabilidade & Auditoria**
- *Auditoria:* `campo.criado`, `campo.atualizado`, `campo.desativado` (com `user_id`, nome do campo, sem valores padrão sensíveis).
- *Logs:* contagem de campos por tipo de cliente, sem valores.
- *Sanitização:* não se aplica a metadados de catálogo; campos de dado do cliente seguem a regra da V1.
- *Banco:* qualquer mudança de consulta exige `[sqlx-prepare]` para regenerar `.sqlx`.

**Critério de aceite:** o tenant cria, edita e desativa campos; o conjunto mínimo está definido e validado.

### V5 — Validação e entrega

**Entregas**
- `dart analyze` e `dart format` nos módulos alterados, na máquina local.
- `cargo fmt` no crate alterado, na máquina local. Testes **só na CI** (regra do projeto).
- CI verde: Flutter (widgets da ficha), Rust (vínculo, whitelist, extração), Python (extração).
- Ensaio na dev: editar contato, vincular, marcar "Não atender", conversar com a IA e conferir a sugestão.
- Conferir no `audit_log` cada evento listado nas fases.

**Observabilidade & Auditoria**
- Verificação final: `grep` por valores de CPF/CNPJ e telefone completo nos logs da dev após o ensaio (zero ocorrências).

**Critério de aceite:** checklist do plano canônico conferido pelo dono do produto.

## Riscos

- **Termo "lista branca":** se D1 não for decidida, a tela nova pode fazer o sistema parar de atender um cliente. V2 depende de D1.
- **Dados pessoais pela IA:** CPF, CNPJ e endereço. Sem validação e sem auditoria, V3 não entra em produção.
- **Dependência entre módulos:** a ficha do Kanban usa casos de uso do `tenant_module`.
- **Documentação não verificada:** pydantic 2.12 e sqlx 0.9 sem checagem contra a documentação atual (ver `info_aux`).
- **Contrato gRPC:** V3 e V2 (opção b) mexem em `admin.proto`.

## Status do workflow

- Scaffold do plano canônico (`scaffoldPlan`), `workflow-init` e `plan link`: **pendentes**. O MCP dotcontext está fora do ar (timeout). Quando voltar, executar os três passos da etapa 5 da skill `plan-restructuring`.

## Status de execução (18/10/2026)

- **Implementado na branch `feature/cadastro-cargo-segmento-obs`:**
  - Migração `0052`: `cargo`, `segmento`, `observacoes` em `oraculo_contato`; `cargo_responsavel` em `oraculo_cliente`.
  - Contrato: campos novos em `MyContato`, `UpdateMyContatoRequest`, `DadosMyCliente`; `ObterContatoDoAtendimentoResponse` com e-mail, cargo, segmento, observações e cliente vinculado; RPC `GetMyCliente`.
  - Servidor: leitura e escrita dos campos; `ContatoComFoto` traz o cliente vinculado; `GetCliente` no `data_postgres`.
  - App Windows: seção "Contato e cliente" no topo da ficha do atendimento, com edição de contato, edição e criação de cliente, vínculo e desvínculo.
- **Pendente:** CI da branch, merge na `dev`, release beta com o app novo e validação no app instalado.
- **Não feito:** a validação de CPF/CNPJ com dígito verificador (V3) e a extração pela conversa (V3), que dependem de D2 já decidida e ficam para a próxima fase.

## Status de verificação (28/10/2026)

- **Auditoria da V1 e da V2 confirmada no servidor:** `cliente.criado`, `cliente.alterado`, `contato.vinculado_cliente`, `contato.desvinculado_cliente`, `contato_editado` e `whatsapp.numero_ignorado.criado/alterado/removido` (`server/apps/data_postgres/src/main.rs`). Divergência de nome: o código usa `contato_editado` (com underline), não `contato.editado`; manter o que existe e registrar como convenção.
- **V2 "Não atender":** botão na ficha do contato com confirmação, usando o mesmo RPC da tela de números ignorados. No ar a partir de `3f715d31`, mergeado em `dev` (`9cf91124`).
- **V4, catálogo de campos:** já liberado (ver acima).
- **V3, validação de documento:** o servidor valida só o tamanho de CPF (11) e CNPJ (14) em `data_postgres/src/main.rs` (~6936). **Falta o dígito verificador.** Decisão pendente: rejeitar documento inválido ao salvar (bloqueia edição de cliente antigo com documento inválido até corrigir) ou só avisar.
- **V3, extração pela conversa:** não iniciada. Depende da decisão acima e da conferência de `pydantic` 2.12 na documentação atual.
- **Release beta.9:** publicada com build, auto-update e feed verificados. Validação no app pendente.

## Validação no app (29/10/2026)

- **Release `0.2.0-beta.9`:** validada pelo dono do produto no app instalado.
- **Entregue e validada:** cadastro de contato e cliente na ficha, vínculo e desvínculo, auditoria, e "Não atender este número".
- **Pendente para fechar a V3:** decisão sobre o advisory `RUSTSEC-2026-0387` (`crypto-bigint` via `aws-sigv4`), que hoje reprova o job de advisories na `dev` e na branch `feature/validacao-documentos-cliente`.
