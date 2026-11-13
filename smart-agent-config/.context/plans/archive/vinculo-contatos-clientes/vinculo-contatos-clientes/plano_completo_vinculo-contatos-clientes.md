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
- **V3, validação de documento:** feita. `cpf_valido` e `cnpj_valido` (dígito verificador) em `data_postgres/src/main.rs`, aplicados ao salvar cliente e à IA (`campos_extraidos.rs`). Documento inválido vindo da IA é descartado; ao salvar manualmente o servidor recusa com "CPF/CNPJ inválido".
- **V3, extração pela conversa:** feita para CEP, e-mail, endereço (só campo vazio, com frase de origem) e documento (dígito verificador). A IA é orientada a não devolver CPF/CNPJ com número de dígitos errado.
- **V3, sugestão de vínculo:** feita. "Pela conversa, parece ser X. Vincular" quando um cliente bate com o documento; "Criar cliente com estes dados?" quando nenhum bate (documento e nome do contato).
- **V4, inventário:** feito em `inventario-campos-v4.md`.
- **V4, conjunto mínimo (D3, decidida por nós):** cliente exige nome, tipo pf/pj e o documento do tipo na criação; na alteração só se olha o que mudou. Feito no servidor (`validar_minimo_do_cliente`, merge `999a6371`).
- **Convenção de auditoria (fechamento da revisão):** os eventos já gravados no histórico mantêm o nome que têm (`contato_editado`, `campo_personalizado.*`, `whatsapp.numero_ignorado.*`), porque renomear quebra a trilha existente. Os eventos novos desta fase seguem o nome do plano: `contato.vinculo_sugerido_ia` (com `atendimento_id` e `cliente_id`, nunca o documento). `whitelist.*` do plano equivale a `whatsapp.numero_ignorado.*` no código.
- **V3, frase de origem obrigatória (fechamento):** todo campo de cartão extraído pela IA só é gravado se a frase devolvida (`frase_origem`) estiver, inteira, na mensagem de origem e o valor de texto estiver na frase. Sem isso, conta como `sem_frase_de_origem` no log do servidor. Endereço já exigia o mesmo.
- **V1, busca por telefone (fechamento):** a busca de clientes casa telefone pelos dígitos, com 4 dígitos ou mais.
- **V1/V5, CPF/CNPJ fora do log (fechamento):** o `Debug` de `DadosCliente` e `ClienteResumo` mascara o documento. Não se usou `SecretString` porque o campo atravessa cerca de 50 pontos de código e o risco que o plano quer evitar é o de log.
- **V3, campo inválido vira pergunta:** feito pelo mecanismo que já existia. Valor inválido não é gravado, então o campo de cartão continua pendente e a IA pergunta de novo (`ResolverCamposAtendimento`, campos com `extrair_automaticamente`). O prompt também pede para não devolver CPF/CNPJ com dígitos errados.
- **D1 e D2:** decididas no próprio plano, ambas em (a).
- **Release beta.9:** publicada com build, auto-update e feed verificados. Validação no app pendente.

## Validação no app (29/10/2026)

- **Release `0.2.0-beta.9`:** validada pelo dono do produto no app instalado.
- **Entregue e validada:** cadastro de contato e cliente na ficha, vínculo e desvínculo, auditoria, e "Não atender este número".
- **Pendente para fechar a V3:** decisão sobre o advisory `RUSTSEC-2026-0387` (`crypto-bigint` via `aws-sigv4`), que hoje reprova o job de advisories na `dev` e na branch `feature/validacao-documentos-cliente`.

## Decisão sobre `minutos_inatividade_encerra` (29/10/2026)

Mantido, sem remoção. O agendador de arquivamento foi removido e o campo não afeta mais o fluxo de atendimento. Remover exige: retirar o campo de `admin.proto` (com reserva do número 33 e do 11), regenerar `generated/fbs` e os stubs Dart, reescrever o SQL de `config_avancada.rs` e regenerar o cache `.sqlx`, e mudar a ferramenta MCP `configuracao_tenant.py`, que expõe o parâmetro a agentes externos (quebra de contrato). Só vale fazer com aprovação explícita do dono do produto.

## D4 — o que a IA pode gravar no cliente (definido em 31/10/2026)

Situação: hoje a IA grava só campos do cartão. Nenhum campo base do cliente é alterado por ela.

Regra adotada (padrão conservador, revisável pelo dono do produto):

1. **Só preenche campo vazio.** Nunca sobrescreve valor já existente, nem o do atendente.
2. **Nunca grava identidade nem documento.** Nome fantasia, razão social, CPF e CNPJ ficam de fora: um documento errado vincula a pessoa errada. A IA só sugere; o atendente confirma (D2).
3. **Pode preencher, depois de validar:** e-mail (formato), CEP (8 dígitos), logradouro, número, complemento, bairro, cidade e UF (duas letras).
4. **Observações, segmento e cargo ficam com o atendente**: são texto livre e a IA tende a inventar.
5. **Toda gravação exige a frase do cliente que originou o valor.** Sem frase, não grava.
6. **Auditoria:** `cliente.dado_alterado_ia` com nome do campo e `message_id` de origem; valor fora do log.
7. **Visível e reversível:** campo preenchido pela IA aparece marcado na ficha, e o atendente pode editar ou limpar.

Fora de escopo desta decisão: a implementação (schema de extração para campos do cliente no `ia_engine`, validação no servidor e marcação na ficha). É a próxima fatia da V3.

## Revisão final (10/11/2026)

Cada item do plano foi conferido contra o código da `dev` (merge `930cde8e`), sem usar as notas de status acima como prova. O que mudou nesta revisão (branch `feature/vinculo-revisao-final`):

**V3 — a frase de origem tem de sustentar o valor, não só existir na mensagem.** Antes, data, lista e número só exigiam que a frase estivesse na rajada: com "oi" como frase a IA gravava qualquer data. Agora, no servidor (`campos_extraidos.rs`, aplicado em `gravar_campos_extraidos`):

- **data:** a frase traz o dia — `03/05` ou ISO (dia, mês e ano escrito têm de bater), o número do dia, o dia por extenso, o dia da semana do valor, ou `hoje`/`amanhã`/`depois de amanhã` (um dia de folga para o fuso). Mês citado por nome tem de ser o do valor. "Fim do mês" não sustenta data: o campo segue pendente e a IA pergunta.
- **lista:** a frase traz o rótulo, o id, ou uma palavra da opção que nenhuma outra opção tem.
- **número:** se a frase tem algarismos, um deles é o valor (`1.500`, `1 500`, `2 mil`, `10k`). Número por extenso continua valendo só pela frase.
- **booleano:** sem forma verificável além da frase; segue como estava.
- O prompt dos dois motores avisa a regra. O motor Jev passou a enviar data em ISO com o trecho que o próprio código lê como aquela data (`frase_da_data`); antes a data nunca saía.

**V3 — CPF/CNPJ com espaço.** Servidor, Jev e app usam a mesma regra: além do documento sem espaço (com ou sem máscara), valem os blocos da máscara oficial separados por um espaço (`529 982 247 25`, `11 222 333 0001 81`). Fora desse desenho o espaço separa números diferentes. O Jev aceitava espaço e quebra de linha entre quaisquer dígitos e o servidor recusava a frase; o Jev foi apertado e o servidor passou a aceitar só o desenho exato.

**V3 — sugestão de vínculo sem falso negativo.** A busca do cliente pelo documento saiu do handler e foi para a transação que grava o campo (`cliente_do_documento_sem_vinculo`): se a busca falha, o valor também não entra e a próxima extração refaz as duas coisas. Antes, uma falha de busca deixava o documento gravado e a sugestão sem trilha para sempre. O documento não sai mais do adaptador (o resumo leva só ids de cliente). A comparação é por dígitos dos dois lados, então cadastro antigo com documento mascarado também é achado.

**V3 — origem do valor.** O `mensagem_origem_id` do campo passa a ser a mensagem da rajada que traz a frase, não sempre a última.

**V1 — busca por documento com máscara.** `ListClientes` casa `529.982.247-25` com o documento gravado só em dígitos (e o inverso), quando o termo não tem letra. O campo da tela diz "Nome, CPF/CNPJ ou telefone". A lista de "Vincular a cliente" ignora resposta de busca antiga que chega depois da atual.

**V1 — nome do perfil do WhatsApp.** O plano pedia e a ficha não mostrava: agora aparece "No WhatsApp: …" quando difere do nome do cadastro. "Criar cliente com estes dados?" usa esse nome quando o contato não tem nome, em vez do telefone.

**V1/V4 — documento repetido.** Criar ou alterar cliente com CPF/CNPJ que já existe no tenant devolvia erro de banco genérico. Agora devolve conflito com mensagem legível, sem o documento. Acontecia quando o cliente existente estava inativo (a busca da sugestão não o mostra, e a tela oferecia "Criar").

**V1 — auditoria do vínculo.** `contato.vinculado_cliente` e `contato.desvinculado_cliente` levam `origem: "atendente"`.

**V1 — auditoria da edição do contato.** `contato_editado` levava só o id; o plano pede os nomes dos campos alterados. O adaptador lê o contato antes do `UPDATE`, na mesma transação, e o evento leva `campos` com o que mudou de fato (a tela manda o formulário inteiro). Nunca o valor.

**V2 — telefone mascarado na auditoria.** A descrição de `whatsapp.numero_ignorado.criado` e `.alterado` levava o número completo. Agora só os quatro últimos dígitos, como o `worker` e o `webhook_ingress` já faziam.

**Decisões desta revisão**

- **Mensagem da rajada sem id persistido:** não foi mexido. O id só falta se a resposta do `PersistMessage` vier sem `message_id`, o que o código atual não faz. Quando falta, a frase daquela mensagem não é verificável e o campo não é gravado — falha fechada, que é o comportamento certo.
- **Spans `contato.editar` / `contato.vincular` / `ia.extrair_campos`:** os spans existem com o nome do RPC (`UpdateContato`, `VincularContatoCliente`, `ia.campos_extraidos`) e os campos pedidos (`tenant_id`, ids, contagens por motivo). Renomear quebraria painéis e alertas já montados sobre esses nomes; ficou como convenção, igual aos nomes de evento de auditoria.
- **`SecretString` para CPF/CNPJ:** mantida a decisão de 28/10 (`Debug` mascarado). O documento agora nem sai do adaptador na sugestão de vínculo.
- **`RUSTSEC-2026-0459` (`libsqlite3-sys` 0.37, SQLite do `local_engine`):** não corrigido e não ignorado. A correção exige `libsqlite3-sys >= 0.39.0`; o `sqlx-sqlite 0.9.0` exige `< 0.38.0`, e o sqlx só subiu o limite no `main` (PR #4502, 08/11/2026), sem versão publicada. Os atalhos (sqlx do git, cópia local do `sqlx-sqlite`) trocam o driver Postgres de todos os serviços ou quebram o `cargo chef` da imagem do servidor. O motivo, o risco aceito e o passo a passo da correção estão em `server/.cargo/audit.toml`.

**Sem verificação nesta revisão:** o ensaio manual na dev (V5: editar, vincular, "Não atender", conversar com a IA e conferir a sugestão no app) e o `grep` de CPF/CNPJ nos logs da dev depois do ensaio. Dependem de uma pessoa no app e de acesso ao VPS, que esta revisão não usa.

## Fechamento das pendências (13/11/2026)

Partida: `dev` em `bb01089a` (CI `43107056175` e deploy `43107056126` verdes). Branch `feature/vinculo-fechamento-final`. A conferência da revisão final deixou seis pendências; o estado de cada uma:

**1. Teste direto do encadeamento gravação → sugestão de vínculo — feito.** O trecho de `gravar_campos_extraidos` que grava o valor e procura o cliente virou a função `gravar_valor_da_ia_e_sugerir_vinculo` (`server/crates/infrastructure_postgres/src/clientes/clientes.rs`), chamada pelo adaptador no mesmo ponto e na mesma transação; o comportamento não mudou. A extração foi necessária porque o adaptador mora no binário do `data_postgres`, cujos testes são unitários por regra (sem banco), e o encadeamento só se prova com banco. O teste de integração `test_valor_da_ia_e_sugestao_de_vinculo_na_mesma_transacao` (`server/crates/infrastructure_postgres/tests/clientes/mod.rs`) confirma transações de verdade e cobre:

- busca falha → o erro chega a quem chama e o valor **não** fica gravado;
- busca ok → o valor entra e o cliente do documento é sugerido;
- documento regravado igual (o chamador não manda documento) → grava, não busca, não sugere;
- gente no caminho (valor manual) → não grava e nem busca.

A falha da busca é provocada com um contexto que tem `atendimentos:write` e não tem `clientes:read`: é a falha que a função de busca devolve de verdade, sem injeção de defeito. Limite do teste: ele não passa pelo laço de `gravar_campos_extraidos` (guardas de slug, frase e piso, que já têm testes próprios em `campos_extraidos.rs`); o que liga as duas partes no adaptador é um `?`.

**2. Teste direto de `MSG_DOCUMENTO_REPETIDO` — feito.** A conversão de `UniqueViolation` em conflito saiu dos dois handlers para a função pura `erro_ao_gravar_cliente` (`server/apps/data_postgres/src/main.rs`). Três testes unitários: a função (unicidade vira `Conflict` com a mensagem fixa, sem o texto do banco; outra falha segue a conversão padrão) e os dois handlers, `CreateCliente` e `UpdateCliente`, com o store simulado devolvendo `UniqueViolation` — resposta de erro `CONFLICT`, com a mensagem, sem o documento e sem linha de auditoria.

**3. Teste direto de `frase_da_data` — feito.** `test_frase_da_data_devolve_o_trecho_que_da_a_mesma_data`, em `ia_engine_jev/tests/unit/test_jev_decisoes.py`, chama a função pelo nome: data por extenso, numérica, relativa com e sem acento, dia da semana, duas datas na mensagem, dependência de `hoje` e os casos sem frase.

**4. Advisories sem registro — registrados, sem exceção.** `server/.cargo/audit.toml` ganhou o bloco "AVISOS PERMITIDOS, SEM EXCEÇÃO DE PROPÓSITO", com motivo, dono e data de revisão (11/12/2026). O campo `ignore` não mudou (segue só com `RUSTSEC-2026-0235`) e o `Cargo.lock` não foi tocado. São os cinco avisos que o `cargo audit` lista como "allowed warnings" no CI `43107056175`:

| Aviso | Crate | Tipo | Correção |
| --- | --- | --- | --- |
| `RUSTSEC-2026-0386` | `tokio` 1.52.3 | `unsound` (`AsyncFd::new` viola I/O safety) | `tokio >= 1.53.3` |
| `RUSTSEC-2026-0486` | `rustix` 1.1.4 (via `tempfile`) | `unsound` (funções de xattr) | `rustix >= 1.1.6` |
| sem ID | `chacha20` 0.10.0 (via `rand` 0.10.1) | `yanked` | `cargo update -p chacha20` |
| sem ID | `spin` 0.9.8 (via `flume` e `multer`) | `yanked` | `cargo update -p spin@0.9.8` |
| sem ID | `spin` 0.10.0 (via `crc-fast`) | `yanked` | `cargo update -p spin@0.10.0` |

Os avisos "sem ID" são versões retiradas do crates.io pelo autor (`yanked`), não advisories. Nenhum código do workspace chama `AsyncFd` nem as funções de xattr do `rustix`. **Continua pendente, fora deste plano:** a correção de verdade é atualizar as dependências. Subir o `tokio` troca o runtime de todos os serviços e do `local_engine`; pede plano próprio, com CI, ensaio na dev e do instalador.

**5. `RUSTSEC-2026-0459` (`libsqlite3-sys` 0.37) — mantido como está, sem exceção.** Reconferido em 13/11/2026 no crates.io: o `sqlx-sqlite 0.9.0` continua sendo o último publicado e continua exigindo `libsqlite3-sys < 0.38.0`; a correção está no `libsqlite3-sys >= 0.39.0`. Não há correção segura e verificável pela CI hoje. O texto de `server/.cargo/audit.toml` descreve o estado real e o caminho (quatro passos, quando o sqlx publicar a versão com o PR #4502); recebeu a data da reconferência, o dono e a próxima revisão (11/12/2026). O job "Dependências — advisories RustSec" segue vermelho por este item, de propósito; ele é informativo (`continue-on-error`) e não bloqueia CI nem deploy.

**6. V5 manual — pendência do dono do produto.** Não dá para fazer daqui: exige uma pessoa no app instalado e acesso ao VPS da dev. Passos:

*a) Ensaio no app (tenant de teste da dev, app na versão da `dev`).* Anotar a hora de início. Usar um contato de teste e os documentos de teste `529.982.247-25` (CPF) e `11.222.333/0001-81` (CNPJ).

1. Na ficha de um atendimento, editar o contato (nome, e-mail, cargo) e salvar.
2. Criar um cliente PF com o CPF de teste. Tentar criar outro com o mesmo CPF: a tela tem de mostrar "já existe um cliente com este CPF/CNPJ — procure por ele na lista de clientes, incluindo os inativos".
3. Vincular o contato ao cliente e desvincular.
4. Com o contato desvinculado, mandar pelo WhatsApp de teste uma mensagem com o CPF ("meu cpf é 529.982.247-25") num atendimento que tenha campo de cartão do tipo CPF com extração ligada. A ficha tem de mostrar "Pela conversa, parece ser … Vincular". Mandar o CPF de novo: a sugestão não se repete na trilha.
5. Vincular o contato de novo e mandar uma mensagem com CEP e e-mail: os campos vazios do cadastro são preenchidos e aparecem marcados como vindos da IA.
6. Na ficha do contato, marcar "Não atender este número", confirmar, mandar mensagem e conferir que o bot não responde. Desmarcar ao final.

*b) `audit_log`.* No VPS, com o usuário que opera o Docker. O `psql` usa as variáveis do próprio contêiner; nenhuma senha aparece:

```bash
docker compose -p smart-core-v2-dev exec -T postgres \
  sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' <<'SQL'
SELECT timestamp, event, message, context
FROM audit_log
WHERE timestamp > now() - interval '2 hours'
  AND (event LIKE 'cliente.%' OR event LIKE 'contato%'
       OR event LIKE 'whatsapp.numero_ignorado.%')
ORDER BY timestamp;
SQL
```

Tem de haver ao menos uma linha de cada: `contato_editado` (com `campos`), `cliente.criado`, `contato.vinculado_cliente` e `contato.desvinculado_cliente` (com `origem: "atendente"`), `contato.vinculo_sugerido_ia` (uma só, com `atendimento_id` e `cliente_id`), `cliente.dado_alterado_ia` e `contato.dado_alterado_ia` (com `campos` e `message_id`), `whatsapp.numero_ignorado.criado` e `.removido` (telefone só com os quatro últimos dígitos). Em nenhuma linha pode aparecer CPF, CNPJ, e-mail, CEP ou telefone completo — nem em `message`, nem em `context`.

*c) `grep` nos logs da dev.* Trocar `TELEFONE` pelo número completo do contato de teste, só dígitos:

```bash
docker compose -p smart-core-v2-dev logs --no-color --since 2h 2>&1 \
  | grep -cE '52998224725|529\.982\.247-25|11222333000181|11\.222\.333/0001-81|TELEFONE'
```

O resultado tem de ser `0`. Se não for, repetir sem o `-c`, anotar o serviço e a linha, e abrir correção antes de fechar a V5.

*d) Fechamento.* Com a, b e c conferidos, registrar a data nesta seção e dar a V5 por aceita ("checklist do plano canônico conferido pelo dono do produto").

**O que continua aberto depois deste fechamento:** a V5 manual (item 6), a atualização de `tokio`, `rustix`, `chacha20` e `spin` (item 4) e o `RUSTSEC-2026-0459` (item 5, à espera do sqlx).
