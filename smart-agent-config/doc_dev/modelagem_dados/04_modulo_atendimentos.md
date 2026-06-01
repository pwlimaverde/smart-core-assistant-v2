# Módulo Atendimentos & Mensageria

Este documento descreve os modelos residentes no **Banco de Dados do Tenant** responsáveis pelo ciclo de vida dos atendimentos, envio e recepção de mensagens, controle de histórico de movimentação física no Kanban, anotações internas dos atendentes e gerenciamento de metadados dinâmicos (campos personalizados).

---

## Diagrama de Entidades (Atendimentos & Mensagens)

```mermaid
erDiagram
    Contato ||--o{ Atendimento : "has"
    Departamento ||--o{ Atendimento : "belongs to"
    FluxoAtendimento ||--o{ Atendimento : "belongs to"
    EtapaFluxo ||--o{ Atendimento : "resides in"
    Atendente ||--o{ Atendimento : "assigned to"
    Atendimento ||--o{ Mensagem : "contains"
    Mensagem ||--o{ Mensagem : "replies to (mensagem_citada)"
    Atendimento ||--o{ MovimentoFluxo : "generates"
    EtapaFluxo ||--o{ MovimentoFluxo : "tracked in (origem/destino)"
    Atendente ||--o{ MovimentoFluxo : "moved by"
    Atendimento ||--o{ ValorCampoAtendimento : "has dynamic"
    CampoPersonalizado ||--o{ ValorCampoAtendimento : "defines structure for"
    Atendimento ||--o{ EtiquetaAtendimento : "has"
    Etiqueta ||--o{ EtiquetaAtendimento : "defines"
    Atendimento ||--o{ Nota : "has internal"
```

---

## 1. Módulo: `atendimentos`

### `StatusAtendimento`
Enumeração que controla o ciclo de vida geral do atendimento (utilizado principalmente para compatibilidade e SLAs).

*   *Opções do Enum (TextChoices):*
    *   `fila` (Fila): Aguardando atendimento ou interação humana inicial.
    *   `em_atendimento` (Em Atendimento): Operador humano ativo no chat.
    *   `pendencia` (Pendência): Aguardando retorno de informações externas ou contato.
    *   `resolvido` (Resolvido): Atendimento concluído com sucesso.
    *   `cancelado` (Cancelado): Atendimento encerrado sem resolução.
    *   `arquivado` (Arquivado): Removido da listagem do painel ativo.
*   *Aliases de Compatibilidade (definidos em tempo de runtime):*
    *   `EM_ANDAMENTO` $\rightarrow$ `EM_ATENDIMENTO`
    *   `AGUARDANDO_ATENDENTE` $\rightarrow$ `FILA`
    *   `AGUARDANDO_CONTATO` $\rightarrow$ `PENDENCIA`

---

### `TipoMensagem`
Especificação do tipo de mídia trafegada no WhatsApp.

*   *Opções do Enum (TextChoices):*
    *   `extendedTextMessage` (Texto Formatado)
    *   `imageMessage` (Imagem)
    *   `videoMessage` (Vídeo)
    *   `audioMessage` (Áudio)
    *   `documentMessage` (Documento)
    *   `stickerMessage` (Sticker)
    *   `locationMessage` (Localização)
    *   `contactMessage` (Contato/vCard)
    *   `listMessage` (Lista Interativa)
    *   `buttonsMessage` (Botões de Ação)
    *   `pollMessage` (Enquete)
    *   `reactMessage` (Reação/Emoji)

---

### `TipoRemetente`
Identifica quem originou o disparo da mensagem.

*   *Opções do Enum (TextChoices):*
    *   `contato` (Contato): Mensagem inbound do cliente final.
    *   `bot` (Bot/Sistema): Mensagem automática gerada pela IA ou rotinas de trigger.
    *   `atendente_humano` (Atendente Humano): Disparo manual de operador logado no painel.

---

### `Atendimento`
A entidade principal que une o cliente final ao departamento, fluxo e operador responsável.

*   **Nome da Tabela:** `oraculo_atendimento`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `contato_id` (INT, Chave Estrangeira, Não Nulo): Relação com `Contato`. Cascade ao deletar.
    *   `departamento_id` (INT, Chave Estrangeira, Opcional/Nulo): Departamento atual do atendimento. Seta nulo em deleção.
    *   `fluxo_atendimento_id` (INT, Chave Estrangeira, Opcional/Nulo): Fluxo ativo no qual o card reside. Seta nulo em deleção.
    *   `status` (VARCHAR(20), Padrão: `"fila"`): Status geral (Enum `StatusAtendimento`).
    *   `etapa_atual_id` (INT, Chave Estrangeira, Opcional/Nulo): Etapa/coluna física no Kanban do fluxo (referencia `EtapaFluxo`). Seta nulo em deleção.
    *   `data_inicio` (TIMESTAMPTZ, Não Nulo): Registra a data/hora em que o atendimento foi aberto (gerado automaticamente).
    *   `data_fim` (TIMESTAMPTZ, Opcional/Nulo): Registra a data/hora em que o atendimento foi fechado (status virou `resolvido`, `cancelado` ou `arquivado`).
    *   `data_ultima_mensagem` (TIMESTAMPTZ, Opcional/Nulo): Usado para SLAs e ordenação de chats.
    *   `assunto` (VARCHAR(200), Opcional/Nulo): Título ou descrição curta do atendimento.
    *   `prioridade` (VARCHAR(10), Padrão: `"normal"`): Grau de urgência.
        *   *Opções:* `baixa`, `normal`, `alta`, `urgente`.
    *   `atendente_humano_id` (INT, Chave Estrangeira, Opcional/Nulo): Operador humano ativo no atendimento. Seta nulo em deleção.
    *   `contexto_conversa` (JSONB, Padrão: `{}`): Estrutura de memória de curto prazo do bot (variáveis temporárias da conversa).
    *   `historico_status` (JSONB, Padrão: `[]`): Registros estruturados de mudanças de status para auditorias (contém status, timestamp e observação).
    *   `tags` (JSONB, Padrão: `[]`): Lista de tags aplicadas ao atendimento.
    *   `avaliacao` (INTEGER, Opcional/Nulo): Nota de satisfação dada pelo contato (1 a 5).
    *   `feedback` (TEXT, Opcional/Nulo): Texto livre com depoimento ou crítica do cliente sobre o atendimento.
    *   `data_primeira_resposta` (TIMESTAMPTZ, Opcional/Nulo): SLA de primeira resposta. Data/hora que o bot/humano enviou a primeira mensagem outbound.
    *   `bot_pode_atender` (BOOLEAN, Padrão: `True`): Flag de segurança. Se `False`, o Bot de IA é impedido de responder, deixando a conversa exclusiva para operadores humanos.
*   **Regras de Negócio (no Método `save` e `clean`):**
    *   **Histórico Inicial:** Se for um novo atendimento, adiciona automaticamente a entrada "Status inicial" ao JSON de histórico.
    *   **Validações Manuais (`clean()`):**
        *   Se `etapa_atual` for fornecida, exige a definição de um `departamento`.
        *   A `etapa_atual` deve pertencer ao departamento escolhido.
        *   O `fluxo_atendimento` deve pertencer ao departamento escolhido.
        *   A `etapa_atual` deve pertencer ao `fluxo_atendimento`.
*   **Métodos Auxiliares:**
    *   `cliente`: Retorna o primeiro cliente principal associado ao contato do atendimento (propriedade ORM).
    *   `finalizar_atendimento(novo_status, solicitar_feedback)`: Fecha o atendimento, seta o timestamp de término, grava histórico e aciona rotina de envio de mensagem de feedback.
    *   `change_status(novo_status, observacao)`: Altera status gravando logs e ajustando datas de encerramento se necessário.
    *   `assumir_atendimento(atendente_id)`: Atribui o card ao atendente humano e desliga o bot (`bot_pode_atender = False`).
    *   `assign_to_agent(atendente, observacao)`: Executa a atribuição física do operador, alterando o status do atendimento para `em_atendimento` e alinhando departamento e fluxo se houver divergências.
    *   `unassign_agent(observacao)`: Remove o operador e joga o atendimento de volta para a fila (`status = fila`).
    *   `transfer_to_department(departamento, observacao)`: Transfere o atendimento para outro setor, limpa o operador humano atribuído e joga na fila, definindo `bot_pode_atender = False` para que o bot não responda após a transferência de setor.
    *   `apply_flow_by_description(flow_description)`: Helper NLP. Recebe texto no formato `"Fluxo - Departamento"`, localiza a entidade e posiciona o atendimento automaticamente no departamento, fluxo e etapa inicial correspondentes.
    *   `touch_last_message(quando)`: Atualiza o campo `data_ultima_mensagem`.
    *   `transferir_para_humano_com_saudacao(atendente_id, observacao)`: Transfere o atendimento e cria automaticamente uma mensagem de saudação do atendente, injetando sua respectiva API key da instância do Evolution para envio.
*   **Índices:**
    *   `oraculo_atendimento_status_dept` (status, departamento)
    *   `oraculo_atendimento_dept_msg` (departamento, data_ultima_mensagem)
    *   `oraculo_atendimento_atendente_status` (atendente_humano, status)
    *   `oraculo_atendimento_etapa_atendente` (etapa_atual, atendente_humano)
    *   `oraculo_atendimento_dept_etapa` (departamento, etapa_atual)
    *   `oraculo_atendimento_fluxo` (fluxo_atendimento)
    *   `oraculo_atendimento_prioridade` (prioridade)
    *   `oraculo_atendimento_tags` (tags)
    *   `oraculo_atendimento_bot_pode` (bot_pode_atender)
*   **Ordenação:** Ordenado descrescentemente por `data_inicio`.

---

### `Mensagem`
Armazena todo o histórico de mensagens inbound/outbound do atendimento.

*   **Nome da Tabela:** `oraculo_mensagem`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `atendimento_id` (INT, Chave Estrangeira, Não Nulo): Relação com `Atendimento`. Cascade ao deletar.
    *   `tipo` (VARCHAR(25), Padrão: `"extendedTextMessage"`): Tipo de mídia da mensagem (Enum `TipoMensagem`).
    *   `conteudo` (TEXT, Não Nulo): Texto da mensagem recebida do cliente. Em mídias binárias, pode armazenar transcrição, links ou legenda.
    *   `remetente` (VARCHAR(20), Padrão: `"contato"`): Enum `TipoRemetente`.
    *   `timestamp` (TIMESTAMPTZ, Não Nulo): Registra a data/hora de envio/recebimento.
    *   `message_id_whatsapp` (VARCHAR(100), Opcional/Nulo): Identificador da mensagem gerado pelo WhatsApp (`messageId`/`stanzaId`).
    *   `metadados` (JSONB, Padrão: `{}`): Estrutura com payloads nativos recebidos pelo webhook (Evolution API) incluindo detalhes de áudio, imagem e localizações.
    *   `respondida` (BOOLEAN, Padrão: `False`): Se o bot já processou e disparou retorno físico para esta mensagem.
    *   `lido` (BOOLEAN, Padrão: `False`, Indexado): Se a mensagem inbound já foi visualizada por um atendente humano no painel do chat.
    *   `resposta_bot` (TEXT, Opcional/Nulo): Armazena a resposta em texto sugerida/gerada pelo Bot inteligente.
    *   `intent_detectado` (JSONB, Padrão: `[]`): Lista com as intenções extraídas da mensagem pela IA (ex: `[{"saudacao": "Olá"}]`).
    *   `entidades_extraidas` (JSONB, Padrão: `[]`): Lista de entidades extraídas pela IA (ex: `[{"cnpj": "00.000.000/0001-00"}]`).
    *   `confianca_resposta` (FLOAT, Opcional/Nulo): Score de confiabilidade da resposta gerada pela LLM (entre 0.0 e 1.0).
    *   `arquivo_midia` (VARCHAR(255) / FILE, Opcional/Nulo): Campo para armazenamento binário físico da mídia decodificada (imagens, áudios, PDFs). Salvo no storage local/S3 do tenant sob o caminho gerado por `media_upload_to`.
    *   `analise_midia` (TEXT, Opcional/Nulo): Texto completo da transcrição de áudio, análise OCR ou interpretação visual gerada por LLM multimodal. Usado exclusivamente como contexto da IA.
    *   `resumo_midia` (TEXT, Opcional/Nulo): Resumo sucinto exibido ao atendente no painel do chat (ex: *"Áudio falando sobre atraso no boleto"*).
    *   `mensagem_citada_id` (INT, Chave Estrangeira, Opcional/Nulo): Autorreferência apontando para a `Mensagem` original que foi respondida (Reply). Seta nulo em deleção.
    *   `quoted_preview` (JSONB, Opcional/Nulo): Contém o preview em texto/mídia da mensagem citada caso a mensagem citada seja muito antiga e não exista no banco local.
    *   `status_envio` (VARCHAR(15), Padrão: `"pending"`, Indexado): Rastreamento de leitura do WhatsApp para mensagens outbound.
        *   *Opções:* `pending` (Pendente), `sent` (Enviada), `delivered` (Entregue), `read` (Lida/azul), `failed` (Falhou).
    *   `data_entregue` (TIMESTAMPTZ, Opcional/Nulo): Timestamp de entrega no dispositivo do cliente.
    *   `data_lida` (TIMESTAMPTZ, Opcional/Nulo): Timestamp de leitura azul no aplicativo do cliente.
*   **Métodos Auxiliares:**
    *   `registrar_resposta_bot(resposta, confianca)`: Helper de gravação da resposta da LLM, com validações de consistência do score e atualização de SLA de primeira resposta.
*   **Ordenação:** Ordenado por `timestamp`.

---

### `MovimentoFluxo`
Tabela histórica de transições de colunas do Kanban. Usada para auditar a jornada do cliente e calcular SLAs por etapa do fluxo.

*   **Nome da Tabela:** `oraculo_movimento_fluxo`
*   **Campos:**
    *   `id` (INT, Chave Primária): ID incremental automático.
    *   `atendimento_id` (INT, Chave Estrangeira, Não Nulo): Relação com `Atendimento`. Cascade ao deletar.
    *   `etapa_origem_id` (INT, Chave Estrangeira, Opcional/Nulo): Coluna de onde o card saiu (nulo para novos atendimentos). Seta nulo em deleção.
    *   `etapa_destino_id` (INT, Chave Estrangeira, Não Nulo): Coluna para onde o card entrou. Cascade ao deletar.
    *   `atendente_origem_id` (INT, Chave Estrangeira, Opcional/Nulo): Atendente que efetuou a movimentação de arraste. Seta nulo em deleção.
    *   `atendente_destino_id` (INT, Chave Estrangeira, Opcional/Nulo): Atendente que foi atribuído como responsável no momento da transição. Seta nulo em deleção.
    *   `motivo` (TEXT, Opcional/Nulo): Motivo informado pelo operador para a mudança de etapa.
    *   `dados_complementares` (JSONB, Padrão: `{}`): Metadados complementares.
    *   `automatico` (BOOLEAN, Padrão: `False`): Se a movimentação foi efetuada por regras de IA do bot.
    *   `data_movimento` (TIMESTAMPTZ, Não Nulo): Data/hora da transição (gerado no insert).
    *   `duracao_segundos` (INTEGER, Opcional/Nulo): Registra a quantidade de segundos em que o card permaneceu na coluna anterior (etapa_origem) até ser arrastado para a atual.
*   **Métodos Auxiliares:**
    *   `criar_movimento(atendimento, etapa_destino, atendente_destino, motivo, automatico, atendente_origem, etapa_origem) [Classmethod]`: Cria o registro de movimentação, calcula de forma automática os segundos de permanência da etapa anterior (por diferença de datas), atualiza a etapa atual e o responsável no `Atendimento` e persiste na base.
*   **Índices:**
    *   `oraculo_mov_fluxo_atend_date` (atendimento, data_movimento DESC)
    *   `oraculo_mov_fluxo_dest_date` (etapa_destino, data_movimento DESC)
    *   `oraculo_mov_fluxo_date` (data_movimento)
*   **Ordenação:** Ordenado decrescentemente por `data_movimento`.

---

## 2. Módulo: `campos_personalizados` (Consolidados)

### `EscopoCampo`
Escopo do campo personalizado configurável.

*   *Opções (TextChoices):*
    *   `GLOBAL` $\rightarrow$ Aplica-se a todos os atendimentos do sistema.
    *   `FLUXO` $\rightarrow$ Exibido apenas quando o atendimento estiver em um `FluxoAtendimento` específico.

---

### `TipoCampo`
Tipos primitivos e complexos suportados pelos campos personalizados.

*   *Opções (TextChoices):*
    *   `texto` (Texto)
    *   `numero` (Número)
    *   `data` (Data)
    *   `escolha` (Escolha única - Dropdown)
    *   `multipla_escolha` (Múltipla escolha)
    *   `booleano` (Booleano)

---

### `OrigemValor`
Identifica quem inseriu o dado no campo personalizado.

*   *Opções (TextChoices):*
    *   `MANUAL` $\rightarrow$ Inserido manualmente pelo atendente.
    *   `BOT` $\rightarrow$ Extraído automaticamente pela IA durante a conversa.
    *   `IMPORT` $\rightarrow$ Migrado ou importado via API.

---

### `CampoPersonalizado`
Catálogo de definição de campos extras que o atendente ou o bot podem preencher durante o atendimento.

*   **Nome da Tabela:** `atu_campo_personalizado`
*   **Campos:**
    *   `id` (BIGINT, Chave Primária): ID automático.
    *   `slug` (SLUG, Não Nulo): Slug de sistema (ex: `valor_orcamento`, `nome_pet`).
    *   `nome` (VARCHAR(120), Não Nulo): Nome amigável do campo exibido na interface.
    *   `descricao` (TEXT, Opcional/Vazio): Descrição detalhada do campo. Serve como dica contextual RAG para a IA compreender o que deve extrair.
    *   `escopo` (VARCHAR(10), Padrão: `"GLOBAL"`): Enum `EscopoCampo`.
    *   `fluxo_id` (BIGINT, Opcional/Nulo): Referência lógica ao ID do `FluxoAtendimento` do app `operacional`. Sem constraint de chave estrangeira física.
    *   `tipo` (VARCHAR(20), Padrão: `"texto"`): Tipo de dados do campo (Enum `TipoCampo`).
    *   `opcoes` (JSONB, Padrão: `[]`): Lista com strings de opções válidas (exclusivo para tipos `escolha` e `multipla_escolha`).
    *   `obrigatorio` (BOOLEAN, Padrão: `False`): Se marcado, impede transição no Kanban para etapas que exijam este campo caso esteja em branco.
    *   `extrair_automaticamente` (BOOLEAN, Padrão: `True`): Se marcado, a rotina de NLP da IA tentará de forma proativa identificar e extrair o dado a partir do texto do cliente.
    *   `extrair_hint` (VARCHAR(500), Opcional/Vazio): Instruções específicas em português para ajudar o prompt de extração da IA (ex: *"Extrair apenas números com DDD"*).
    *   `mostrar_no_card` (BOOLEAN, Padrão: `True`): Exibe o valor do campo em formato de tag diretamente no card Kanban.
    *   `ordem` (INTEGER, Padrão: `0`): Prioridade de renderização na aba lateral do chat.
    *   `ativo` (BOOLEAN, Padrão: `True`): Define se o campo está ativo.
    *   `data_criacao` (TIMESTAMPTZ, Não Nulo): Data de inclusão.
    *   `data_atualizacao` (TIMESTAMPTZ, Não Nulo): Data da última modificação.
*   **Restrições e Unicidade:**
    *   `unique_together`: `[["slug", "escopo", "fluxo_id"]]` (Evita duplicação do mesmo slug no mesmo escopo/fluxo).
*   **Índices:**
    *   `atu_campo_escopo_fluxo_idx` (escopo, fluxo_id, ativo)
    *   `atu_campo_extrair_idx` (extrair_automaticamente, ativo)
*   **Ordenação:** Ordenado por `ordem` e depois alfabeticamente por `nome`.

---

### `ValorCampoAtendimento`
Armazena o valor preenchido de um campo personalizado para um determinado atendimento.

*   **Nome da Tabela:** `atu_valor_campo`
*   **Campos:**
    *   `id` (BIGINT, Chave Primária): ID automático.
    *   `atendimento_id` (BIGINT, Não Nulo): ID lógico do `Atendimento` (sem constraint física de FK).
    *   `campo_id` (INT, Chave Estrangeira, Não Nulo): Relação física com `CampoPersonalizado`. Cascade ao deletar.
    *   `valor` (JSONB, Não Nulo): Valor armazenado em formato estruturado coerente com o tipo (ex: string, número, array, booleano).
    *   `origem` (VARCHAR(10), Padrão: `"MANUAL"`): Enum `OrigemValor`.
    *   `confianca` (FLOAT, Opcional/Nulo): Nível de confiança da extração da IA (válido apenas quando `origem = BOT`).
    *   `mensagem_origem_id` (BIGINT, Opcional/Nulo): ID lógico da `Mensagem` a partir da qual a IA efetuou a extração (útil para auditoria).
    *   `editado_por_id` (BIGINT, Opcional/Nulo): ID lógico do `Atendente` que sobrescreveu o campo manualmente.
    *   `data_atualizacao` (TIMESTAMPTZ, Não Nulo): Última atualização do valor.
*   **Restrições e Unicidade:**
    *   `unique_together`: `[["atendimento_id", "campo"]]` (Garante que cada atendimento possua apenas um registro de valor por campo personalizado).
*   **Índices:**
    *   `atu_valor_atend_campo_idx` (atendimento_id, campo)

---

## 3. Módulo: `etiquetas_notas` (Consolidados)

### `Etiqueta`
Catálogo de tags e marcadores coloridos criados pelo administrador do inquilino para categorizar conversas.

*   **Nome da Tabela:** `atu_etiqueta`
*   **Campos:**
    *   `id` (BIGINT, Chave Primária): ID automático.
    *   `nome` (VARCHAR(50), Não Nulo, Único): Nome legível (ex: "Lead Frio", "Cliente VIP").
    *   `cor` (VARCHAR(7), Padrão: `"#a98f71"`): Código de cor hexadecimal do chip.
    *   `descricao` (VARCHAR(200), Opcional/Vazio): Tooltip de explicação da tag.
    *   `ativo` (BOOLEAN, Padrão: `True`): Status de ativação da etiqueta.
    *   `data_criacao` (TIMESTAMPTZ, Não Nulo): Data de inclusão.
*   **Ordenação:** Ordenado alfabeticamente por `nome`.

---

### `EtiquetaAtendimento`
Tabela associativa Muitos para Muitos manual entre Atendimentos e Etiquetas, contendo dados de auditoria do operador que aplicou a tag.

*   **Nome da Tabela:** `atu_etiqueta_atendimento`
*   **Campos:**
    *   `id` (BIGINT, Chave Primária): ID automático.
    *   `atendimento_id` (BIGINT, Não Nulo, Indexado): ID lógico do `Atendimento`.
    *   `etiqueta_id` (INT, Chave Estrangeira, Não Nulo): Relação com `Etiqueta`. Cascade ao deletar.
    *   `aplicada_em` (TIMESTAMPTZ, Não Nulo): Data/hora de aplicação (gerado no insert).
    *   `aplicada_por_id` (BIGINT, Opcional/Nulo): ID lógico do `Atendente` que adicionou o marcador.
*   **Restrições e Unicidade:**
    *   `unique_together`: `[["atendimento_id", "etiqueta"]]` (Garante que a mesma etiqueta não seja aplicada em duplicidade no mesmo atendimento).
*   **Índices:**
    *   `atu_etiq_atend_idx` (atendimento_id)

---

### `Nota`
Anotações e comentários internos textuais adicionados pelos operadores sobre o cliente, invisíveis para o contato final no WhatsApp.

*   **Nome da Tabela:** `atu_nota`
*   **Campos:**
    *   `id` (BIGINT, Chave Primária): ID automático.
    *   `atendimento_id` (BIGINT, Não Nulo, Indexado): ID lógico do `Atendimento`.
    *   `texto` (TEXT, Não Nulo): Conteúdo em texto da nota interna.
    *   `criado_por_id` (BIGINT, Opcional/Nulo): ID lógico do `Atendente` autor da anotação.
    *   `criado_em` (TIMESTAMPTZ, Não Nulo): Data de inserção da nota.
*   **Índices:**
    *   `atu_nota_atend_idx` (atendimento_id, criado_em DESC)
*   **Ordenação:** Notas mais recentes primeiro (`-criado_em`).
