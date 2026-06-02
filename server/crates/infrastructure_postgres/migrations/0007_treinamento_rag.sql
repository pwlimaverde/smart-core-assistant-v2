-- ============================================================
-- Módulo Treinamento & IA (RAG): base de conhecimento vetorial e intenções
-- ============================================================

-- Treinamento: metadados do texto bruto submetido pelo admin do tenant
CREATE TABLE oraculo_treinamento (
    id                     SERIAL PRIMARY KEY,
    tenant_id              UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    tag                    VARCHAR(40) NOT NULL,
    grupo                  VARCHAR(40) NOT NULL,
    conteudo               TEXT,
    treinamento_finalizado BOOLEAN NOT NULL DEFAULT FALSE,
    treinamento_vetorizado BOOLEAN NOT NULL DEFAULT FALSE,
    data_criacao           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_atualizacao       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, tag, grupo)
);

ALTER TABLE oraculo_treinamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_treinamento FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_treinamento_tenant_isolation ON oraculo_treinamento
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_treinamento_tenant_tag_grupo ON oraculo_treinamento (tenant_id, tag, grupo);
CREATE INDEX oraculo_treinamento_tenant_status    ON oraculo_treinamento (tenant_id, treinamento_finalizado, treinamento_vetorizado);

-- Documento: chunks vetorizados (embeddings 1536-dim) para busca semântica
CREATE TABLE oraculo_documento (
    id             SERIAL PRIMARY KEY,
    tenant_id      UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    treinamento_id INT NOT NULL REFERENCES oraculo_treinamento(id) ON DELETE CASCADE,
    conteudo       TEXT,
    metadata       JSONB NOT NULL DEFAULT '{}',
    embedding      VECTOR(1536),   -- compatível com text-embedding-3-small da OpenAI
    ordem          INT NOT NULL DEFAULT 1,
    data_criacao   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE oraculo_documento ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_documento FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_documento_tenant_isolation ON oraculo_documento
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- Índice HNSW para busca por cosseno eficiente (filtro tenant_id na query garante scope)
CREATE INDEX oraculo_documento_embedding_hnsw
    ON oraculo_documento USING hnsw (embedding vector_cosine_ops);

CREATE INDEX oraculo_documento_tenant_trein_ordem ON oraculo_documento (tenant_id, treinamento_id, ordem);

-- QueryTestFeedback: avaliações manuais de qualidade das respostas do bot
CREATE TABLE treinamento_query_test_feedback (
    id                 SERIAL PRIMARY KEY,
    tenant_id          UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    mensagem_original  TEXT NOT NULL,
    resposta_bot       TEXT NOT NULL,
    resposta_corrigida TEXT,
    avaliacao          VARCHAR(10) NOT NULL,
    confiabilidade     FLOAT NOT NULL DEFAULT 0.0,
    entidades_json     JSONB NOT NULL DEFAULT '{}',
    intents_json       JSONB NOT NULL DEFAULT '{}',
    documentos_ids     JSONB NOT NULL DEFAULT '[]',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE treinamento_query_test_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE treinamento_query_test_feedback FORCE  ROW LEVEL SECURITY;
CREATE POLICY treinamento_query_test_feedback_tenant_isolation ON treinamento_query_test_feedback
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX treinamento_query_test_feedback_tenant_created
    ON treinamento_query_test_feedback (tenant_id, created_at DESC);

-- QueryCompose: catálogo de intenções com embeddings para detecção semântica
CREATE TABLE treinamento_querycompose (
    id           SERIAL PRIMARY KEY,
    tenant_id    UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    tag          VARCHAR(40) NOT NULL,
    grupo        VARCHAR(40) NOT NULL,
    descricao    TEXT NOT NULL,
    exemplo      TEXT NOT NULL,
    comportamento TEXT NOT NULL,
    embedding    VECTOR(1536),   -- gerado de to_embedding_text(tag, descricao, exemplo)
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, tag, grupo)
);

ALTER TABLE treinamento_querycompose ENABLE ROW LEVEL SECURITY;
ALTER TABLE treinamento_querycompose FORCE  ROW LEVEL SECURITY;
CREATE POLICY treinamento_querycompose_tenant_isolation ON treinamento_querycompose
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX treinamento_querycompose_embedding_hnsw
    ON treinamento_querycompose USING hnsw (embedding vector_cosine_ops);

CREATE INDEX treinamento_querycompose_tenant_tag  ON treinamento_querycompose (tenant_id, tag);
CREATE INDEX treinamento_querycompose_tenant_date ON treinamento_querycompose (tenant_id, created_at);
