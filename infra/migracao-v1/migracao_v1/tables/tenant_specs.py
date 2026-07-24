"""`TableSpec`s das entidades TENANT_APPS (banco fisico por tenant na v1).

A lista `TENANT_APP_SPECS` esta na ORDEM DE DEPENDENCIA correta — quem roda
o step (ver `steps/run_tenant_apps.py`) deve migrar cada `TableSpec` nessa
ordem, sequencialmente, para o `id_map` de uma entidade estar populado antes
de qualquer `FkRemap` que a referencie.

Todas usam `scope="tenant"` (o `tenant_id` e injetado automaticamente pelo
engine — a v1 nao tem essa coluna, o isolamento la e por banco fisico) e
`id_strategy="map"` (gera id novo v2 + mantem correspondencia — ver
`id_map.py` sobre por que nao tentamos preservar o id original aqui).

Origem das tabelas v1 (confirmado lendo `Meta.db_table` de cada model — ver
`old/.../app/{operacional,clientes,atendimentos,atendimento_unificado,
treinamento,evolution_sync}/models.py`): quase todas ja usam o MESMO nome de
tabela que a v2 (`oraculo_*`, `atu_*`), com excecao do modulo Evolution
(`evolution_sync_*` na v1 -> `whatsapp_*` na v2, ver `whatsapp_specs`
separado por causa da re-cifragem do `api_key`).
"""

from __future__ import annotations

from .spec import ColumnSpec, FkRemap, TableSpec

# ---------------------------------------------------------------------------
# Operacional: departamento -> fluxo -> etapa -> atendente -> app_instance
# ---------------------------------------------------------------------------

DEPARTAMENTO = TableSpec(
    entidade="operacional.departamento",
    v1_table="oraculo_departamento",
    v2_table="oraculo_departamento",
    scope="tenant",
    id_strategy="map",
    columns=[
        ColumnSpec("nome"),
        ColumnSpec("slug"),
        ColumnSpec("descricao"),
        ColumnSpec("ativo"),
        ColumnSpec("telefone_instancia"),
        # api_key: SEM Fernet na origem (doc: "essas NAO tinham Fernet") — copia
        # em texto plano, igual a v1. Debito tecnico documentado no README.
        ColumnSpec("api_key"),
        ColumnSpec("configuracoes"),
        ColumnSpec("metadados"),
        ColumnSpec("data_criacao"),
    ],
)

FLUXO_ATENDIMENTO = TableSpec(
    entidade="operacional.fluxo_atendimento",
    v1_table="oraculo_fluxo_atendimento",
    v2_table="oraculo_fluxo_atendimento",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="data_atualizacao",
    fk_remaps=(FkRemap("departamento_id", "operacional.departamento", nullable=False),),
    columns=[
        ColumnSpec("departamento_id"),
        ColumnSpec("nome"),
        ColumnSpec("descricao"),
        ColumnSpec("ativo"),
        ColumnSpec("data_criacao"),
        ColumnSpec("data_atualizacao"),
    ],
)

ETAPA_FLUXO = TableSpec(
    entidade="operacional.etapa_fluxo",
    v1_table="oraculo_etapa_fluxo",
    v2_table="oraculo_etapa_fluxo",
    scope="tenant",
    id_strategy="map",
    fk_remaps=(FkRemap("fluxo_id", "operacional.fluxo_atendimento", nullable=False),),
    columns=[
        ColumnSpec("fluxo_id"),
        ColumnSpec("nome"),
        ColumnSpec("descricao"),
        ColumnSpec("ordem"),
        ColumnSpec("cor"),
        ColumnSpec("tipo_etapa"),
        ColumnSpec("permite_atribuicao"),
        ColumnSpec("automatico"),
        ColumnSpec("regras_transicao"),
        ColumnSpec("campos_obrigatorios"),
        ColumnSpec("ativo"),
        ColumnSpec("data_criacao"),
    ],
)

ATENDENTE = TableSpec(
    entidade="operacional.atendente",
    v1_table="oraculo_atendente",
    v2_table="oraculo_atendente",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="ultima_atividade",
    fk_remaps=(
        FkRemap("departamento_id", "operacional.departamento", nullable=True),
        FkRemap("fluxo_id", "operacional.fluxo_atendimento", nullable=False),
        # usuario_id: FK para auth_user (CORE, ids preservados 1:1 entre v1/v2
        # no MESMO banco default) — NAO precisa de remap, copiado direto.
    ),
    columns=[
        ColumnSpec("slug"),
        ColumnSpec("telefone"),
        ColumnSpec("nome"),
        ColumnSpec("cargo"),
        ColumnSpec("departamento_id"),
        ColumnSpec("fluxo_id"),
        ColumnSpec("email"),
        ColumnSpec("usuario_id"),
        ColumnSpec("usuario_sistema"),
        ColumnSpec("ativo"),
        ColumnSpec("disponivel"),
        ColumnSpec("max_atendimentos_simultaneos"),
        ColumnSpec("data_ultima_atribuicao"),
        ColumnSpec("horario_trabalho"),
        ColumnSpec("especialidades"),
        ColumnSpec("metadados"),
        ColumnSpec("data_cadastro"),
        ColumnSpec("ultima_atividade"),
    ],
)

APP_INSTANCE = TableSpec(
    entidade="operacional.app_instance",
    v1_table="oraculo_app_instance",
    v2_table="oraculo_app_instance",
    scope="tenant",
    id_strategy="map",
    fk_remaps=(
        FkRemap("departamento_id", "operacional.departamento", nullable=True),
        FkRemap("owner_id", "operacional.atendente", nullable=True),
    ),
    columns=[
        # api_key: SEM Fernet na origem (mesma nota de Departamento acima) —
        # copia em texto plano.
        ColumnSpec("api_key"),
        ColumnSpec("channel"),
        ColumnSpec("display_name"),
        ColumnSpec("departamento_id"),
        ColumnSpec("owner_id"),
        ColumnSpec("active"),
        ColumnSpec("resposta_bot"),
        ColumnSpec("metadata"),
        ColumnSpec("created_at"),
    ],
)

# ---------------------------------------------------------------------------
# Clientes & Contatos
# ---------------------------------------------------------------------------

CONTATO = TableSpec(
    entidade="clientes.contato",
    v1_table="oraculo_contato",
    v2_table="oraculo_contato",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="ultima_interacao",
    columns=[
        ColumnSpec("telefone"),
        ColumnSpec("nome_contato"),
        ColumnSpec("slug"),
        ColumnSpec("email"),
        ColumnSpec("nome_perfil_whatsapp"),
        ColumnSpec("data_cadastro"),
        ColumnSpec("ultima_interacao"),
        ColumnSpec("ativo"),
        ColumnSpec("metadados"),
        # foto_perfil: copiado como estava (path relativo da v1) NESTE step;
        # o step 7 (`run_media.py`) faz o upload para o R2 e sobrescreve esta
        # coluna com a URL/key definitiva, casando pelo id_map desta entidade.
        ColumnSpec("foto_perfil"),
        ColumnSpec("foto_perfil_url_origem"),
    ],
)

CLIENTE = TableSpec(
    entidade="clientes.cliente",
    v1_table="oraculo_cliente",
    v2_table="oraculo_cliente",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="ultima_atualizacao",
    columns=[
        ColumnSpec("nome_fantasia"),
        ColumnSpec("slug"),
        ColumnSpec("razao_social"),
        ColumnSpec("tipo"),
        ColumnSpec("cnpj"),
        ColumnSpec("cpf"),
        ColumnSpec("telefone"),
        ColumnSpec("site"),
        ColumnSpec("ramo_atividade"),
        ColumnSpec("observacoes"),
        ColumnSpec("cep"),
        ColumnSpec("logradouro"),
        ColumnSpec("numero"),
        ColumnSpec("complemento"),
        ColumnSpec("bairro"),
        ColumnSpec("cidade"),
        ColumnSpec("uf"),
        ColumnSpec("pais"),
        ColumnSpec("data_cadastro"),
        ColumnSpec("ultima_atualizacao"),
        ColumnSpec("ativo"),
        ColumnSpec("metadados"),
    ],
)

CLIENTE_CONTATOS = TableSpec(
    entidade="clientes.cliente_contatos",
    v1_table="oraculo_cliente_contatos",
    v2_table="oraculo_cliente_contatos",
    scope="tenant",
    id_strategy="natural",
    natural_conflict_cols=("cliente_id", "contato_id"),
    fk_remaps=(
        FkRemap("cliente_id", "clientes.cliente", nullable=False),
        FkRemap("contato_id", "clientes.contato", nullable=False),
    ),
    columns=[
        ColumnSpec("cliente_id"),
        ColumnSpec("contato_id"),
    ],
)

# ---------------------------------------------------------------------------
# Atendimentos: ticket, mensagens, kanban, campos dinamicos, etiquetas, notas
# ---------------------------------------------------------------------------

ATENDIMENTO = TableSpec(
    entidade="atendimentos.atendimento",
    v1_table="oraculo_atendimento",
    v2_table="oraculo_atendimento",
    scope="tenant",
    id_strategy="map",
    # Sem coluna de "ultima atualizacao" generica no modelo v1 — `data_ultima_mensagem`
    # so muda quando chega mensagem nova, nao cobre toda edicao (ex.: mudanca de
    # status/etiqueta). Limitacao documentada no README: modo --since sempre
    # inclui todos os atendimentos (comportamento seguro por padrao, ver delta.py).
    delta_column_v1=None,
    fk_remaps=(
        FkRemap("contato_id", "clientes.contato", nullable=False),
        FkRemap("departamento_id", "operacional.departamento", nullable=True),
        FkRemap("fluxo_atendimento_id", "operacional.fluxo_atendimento", nullable=True),
        FkRemap("etapa_atual_id", "operacional.etapa_fluxo", nullable=True),
        FkRemap("atendente_humano_id", "operacional.atendente", nullable=True),
    ),
    columns=[
        ColumnSpec("contato_id"),
        ColumnSpec("departamento_id"),
        ColumnSpec("fluxo_atendimento_id"),
        ColumnSpec("status"),
        ColumnSpec("etapa_atual_id"),
        ColumnSpec("data_inicio"),
        ColumnSpec("data_fim"),
        ColumnSpec("data_ultima_mensagem"),
        ColumnSpec("assunto"),
        ColumnSpec("prioridade"),
        ColumnSpec("atendente_humano_id"),
        ColumnSpec("contexto_conversa"),
        ColumnSpec("historico_status"),
        ColumnSpec("tags"),
        ColumnSpec("avaliacao"),
        ColumnSpec("feedback"),
        ColumnSpec("data_primeira_resposta"),
        ColumnSpec("bot_pode_atender"),
    ],
)

MENSAGEM = TableSpec(
    entidade="atendimentos.mensagem",
    v1_table="oraculo_mensagem",
    v2_table="oraculo_mensagem",
    scope="tenant",
    id_strategy="map",
    # Idem Atendimento: sem coluna de "ultima atualizacao" (timestamp e so de
    # criacao; read-receipts/respondida podem mudar depois sem tocar `timestamp`).
    delta_column_v1=None,
    fk_remaps=(
        FkRemap("atendimento_id", "atendimentos.atendimento", nullable=False),
        # Auto-referencia (reply/citacao) — seguro pois o engine processa em
        # ordem ASCENDENTE de id_v1 e uma mensagem so pode citar outra
        # CRIADA ANTES dela (id_v1 menor, ja migrada e presente no id_map).
        FkRemap("mensagem_citada_id", "atendimentos.mensagem", nullable=True),
    ),
    columns=[
        ColumnSpec("atendimento_id"),
        ColumnSpec("tipo"),
        ColumnSpec("conteudo"),
        ColumnSpec("remetente"),
        ColumnSpec("timestamp"),
        ColumnSpec("message_id_whatsapp"),
        ColumnSpec("metadados"),
        ColumnSpec("respondida"),
        ColumnSpec("lido"),
        ColumnSpec("resposta_bot"),
        ColumnSpec("intent_detectado"),
        ColumnSpec("entidades_extraidas"),
        ColumnSpec("confianca_resposta"),
        # arquivo_midia: idem foto_perfil — path v1 copiado agora, reescrito
        # pelo step 7 apos upload ao R2.
        ColumnSpec("arquivo_midia"),
        ColumnSpec("analise_midia"),
        ColumnSpec("resumo_midia"),
        ColumnSpec("mensagem_citada_id"),
        ColumnSpec("quoted_preview"),
        ColumnSpec("status_envio"),
        ColumnSpec("data_entregue"),
        ColumnSpec("data_lida"),
    ],
)

MOVIMENTO_FLUXO = TableSpec(
    entidade="atendimentos.movimento_fluxo",
    v1_table="oraculo_movimento_fluxo",
    v2_table="oraculo_movimento_fluxo",
    scope="tenant",
    id_strategy="map",
    delta_column_v1=None,  # tabela somente-insercao (historico de auditoria)
    fk_remaps=(
        FkRemap("atendimento_id", "atendimentos.atendimento", nullable=False),
        FkRemap("etapa_origem_id", "operacional.etapa_fluxo", nullable=True),
        FkRemap("etapa_destino_id", "operacional.etapa_fluxo", nullable=False),
        FkRemap("atendente_origem_id", "operacional.atendente", nullable=True),
        FkRemap("atendente_destino_id", "operacional.atendente", nullable=True),
    ),
    columns=[
        ColumnSpec("atendimento_id"),
        ColumnSpec("etapa_origem_id"),
        ColumnSpec("etapa_destino_id"),
        ColumnSpec("atendente_origem_id"),
        ColumnSpec("atendente_destino_id"),
        ColumnSpec("motivo"),
        ColumnSpec("dados_complementares"),
        ColumnSpec("automatico"),
        ColumnSpec("data_movimento"),
        ColumnSpec("duracao_segundos"),
    ],
)

CAMPO_PERSONALIZADO = TableSpec(
    entidade="atu.campo_personalizado",
    v1_table="atu_campo_personalizado",
    v2_table="atu_campo_personalizado",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="data_atualizacao",
    fk_remaps=(FkRemap("fluxo_id", "operacional.fluxo_atendimento", nullable=True),),
    columns=[
        ColumnSpec("slug"),
        ColumnSpec("nome"),
        ColumnSpec("descricao"),
        ColumnSpec("escopo"),
        ColumnSpec("fluxo_id"),
        ColumnSpec("tipo"),
        ColumnSpec("opcoes"),
        ColumnSpec("obrigatorio"),
        ColumnSpec("extrair_automaticamente"),
        ColumnSpec("extrair_hint"),
        ColumnSpec("mostrar_no_card"),
        ColumnSpec("ordem"),
        ColumnSpec("ativo"),
        ColumnSpec("data_criacao"),
        ColumnSpec("data_atualizacao"),
    ],
)

VALOR_CAMPO = TableSpec(
    entidade="atu.valor_campo",
    v1_table="atu_valor_campo",
    v2_table="atu_valor_campo",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="data_atualizacao",
    fk_remaps=(
        FkRemap("atendimento_id", "atendimentos.atendimento", nullable=False),
        FkRemap("campo_id", "atu.campo_personalizado", nullable=False),
        FkRemap("mensagem_origem_id", "atendimentos.mensagem", nullable=True),
        FkRemap("editado_por_id", "operacional.atendente", nullable=True),
    ),
    columns=[
        ColumnSpec("atendimento_id"),
        ColumnSpec("campo_id"),
        ColumnSpec("valor"),
        ColumnSpec("origem"),
        ColumnSpec("confianca"),
        ColumnSpec("mensagem_origem_id"),
        ColumnSpec("editado_por_id"),
        ColumnSpec("data_atualizacao"),
    ],
)

ETIQUETA = TableSpec(
    entidade="atu.etiqueta",
    v1_table="atu_etiqueta",
    v2_table="atu_etiqueta",
    scope="tenant",
    id_strategy="map",
    delta_column_v1=None,
    columns=[
        ColumnSpec("nome"),
        ColumnSpec("cor"),
        ColumnSpec("descricao"),
        ColumnSpec("ativo"),
        ColumnSpec("data_criacao"),
    ],
)

ETIQUETA_ATENDIMENTO = TableSpec(
    entidade="atu.etiqueta_atendimento",
    v1_table="atu_etiqueta_atendimento",
    v2_table="atu_etiqueta_atendimento",
    scope="tenant",
    id_strategy="natural",
    natural_conflict_cols=("tenant_id", "atendimento_id", "etiqueta_id"),
    fk_remaps=(
        FkRemap("atendimento_id", "atendimentos.atendimento", nullable=False),
        FkRemap("etiqueta_id", "atu.etiqueta", nullable=False),
        FkRemap("aplicada_por_id", "operacional.atendente", nullable=True),
    ),
    columns=[
        ColumnSpec("atendimento_id"),
        ColumnSpec("etiqueta_id"),
        ColumnSpec("aplicada_em"),
        ColumnSpec("aplicada_por_id"),
    ],
)

NOTA = TableSpec(
    entidade="atu.nota",
    v1_table="atu_nota",
    v2_table="atu_nota",
    scope="tenant",
    id_strategy="map",
    delta_column_v1=None,  # notas nao sao editadas, so criadas
    fk_remaps=(
        FkRemap("atendimento_id", "atendimentos.atendimento", nullable=False),
        FkRemap("criado_por_id", "operacional.atendente", nullable=True),
    ),
    columns=[
        ColumnSpec("atendimento_id"),
        ColumnSpec("texto"),
        ColumnSpec("criado_por_id"),
        ColumnSpec("criado_em"),
    ],
)

# ---------------------------------------------------------------------------
# Treinamento & IA (RAG) — embeddings copiados diretamente (mesma dimensao
# 1536 e extensao pgvector nos dois lados; sem reembedding via ia_engine).
# ---------------------------------------------------------------------------

TREINAMENTO = TableSpec(
    entidade="treinamento.treinamento",
    v1_table="oraculo_treinamento",
    v2_table="oraculo_treinamento",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="data_atualizacao",
    columns=[
        ColumnSpec("tag"),
        ColumnSpec("grupo"),
        ColumnSpec("conteudo"),
        ColumnSpec("treinamento_finalizado"),
        ColumnSpec("treinamento_vetorizado"),
        ColumnSpec("data_criacao"),
        ColumnSpec("data_atualizacao"),
    ],
)

DOCUMENTO = TableSpec(
    entidade="treinamento.documento",
    v1_table="oraculo_documento",
    v2_table="oraculo_documento",
    scope="tenant",
    id_strategy="map",
    delta_column_v1=None,  # chunks sao imutaveis apos criados
    fk_remaps=(FkRemap("treinamento_id", "treinamento.treinamento", nullable=False),),
    columns=[
        ColumnSpec("treinamento_id"),
        ColumnSpec("conteudo"),
        ColumnSpec("metadata"),
        # asyncpg nao tem codec nativo para o tipo `vector` do pgvector — lemos
        # como texto (`::text`) e re-inserimos com cast explicito (`::vector`).
        # Mesma dimensao (1536) nos dois lados: copia direta, sem reembedding.
        ColumnSpec("embedding", v1_cast="::text", v2_cast="::vector"),
        ColumnSpec("ordem"),
        ColumnSpec("data_criacao"),
    ],
)

QUERYCOMPOSE = TableSpec(
    entidade="treinamento.querycompose",
    v1_table="treinamento_querycompose",
    v2_table="treinamento_querycompose",
    scope="tenant",
    id_strategy="map",
    delta_column_v1="updated_at",
    columns=[
        ColumnSpec("tag"),
        ColumnSpec("grupo"),
        ColumnSpec("descricao"),
        ColumnSpec("exemplo"),
        ColumnSpec("comportamento"),
        ColumnSpec("embedding", v1_cast="::text", v2_cast="::vector"),
        ColumnSpec("created_at"),
        ColumnSpec("updated_at"),
    ],
)

QUERY_TEST_FEEDBACK = TableSpec(
    entidade="treinamento.query_test_feedback",
    v1_table="treinamento_query_test_feedback",
    v2_table="treinamento_query_test_feedback",
    scope="tenant",
    id_strategy="map",
    delta_column_v1=None,
    columns=[
        ColumnSpec("mensagem_original"),
        ColumnSpec("resposta_bot"),
        ColumnSpec("resposta_corrigida"),
        ColumnSpec("avaliacao"),
        ColumnSpec("confiabilidade"),
        ColumnSpec("entidades_json"),
        ColumnSpec("intents_json"),
        ColumnSpec("documentos_ids"),
        ColumnSpec("created_at"),
    ],
)

# Ordem de execucao — respeita as dependencias de FK (ver FkRemap de cada spec).
TENANT_APP_SPECS: list[TableSpec] = [
    DEPARTAMENTO,
    FLUXO_ATENDIMENTO,
    ETAPA_FLUXO,
    ATENDENTE,
    APP_INSTANCE,
    CONTATO,
    CLIENTE,
    CLIENTE_CONTATOS,
    ATENDIMENTO,
    MENSAGEM,
    MOVIMENTO_FLUXO,
    CAMPO_PERSONALIZADO,
    VALOR_CAMPO,
    ETIQUETA,
    ETIQUETA_ATENDIMENTO,
    NOTA,
    TREINAMENTO,
    DOCUMENTO,
    QUERYCOMPOSE,
    QUERY_TEST_FEEDBACK,
]
