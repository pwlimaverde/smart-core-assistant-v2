-- ============================================================
-- Módulo Atendimentos: tickets, mensagens, Kanban, campos dinâmicos, etiquetas e notas
-- ============================================================

-- Atendimento: entidade principal que une contato, departamento, fluxo e operador
CREATE TABLE oraculo_atendimento (
    id                   SERIAL PRIMARY KEY,
    tenant_id            UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    contato_id           INT NOT NULL REFERENCES oraculo_contato(id) ON DELETE CASCADE,
    departamento_id      INT REFERENCES oraculo_departamento(id) ON DELETE SET NULL,
    fluxo_atendimento_id INT REFERENCES oraculo_fluxo_atendimento(id) ON DELETE SET NULL,
    status               VARCHAR(20) NOT NULL DEFAULT 'fila',
    etapa_atual_id       INT REFERENCES oraculo_etapa_fluxo(id) ON DELETE SET NULL,
    data_inicio          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_fim             TIMESTAMPTZ,
    data_ultima_mensagem TIMESTAMPTZ,
    assunto              VARCHAR(200),
    prioridade           VARCHAR(10) NOT NULL DEFAULT 'normal',
    atendente_humano_id  INT REFERENCES oraculo_atendente(id) ON DELETE SET NULL,
    contexto_conversa    JSONB NOT NULL DEFAULT '{}',
    historico_status     JSONB NOT NULL DEFAULT '[]',
    tags                 JSONB NOT NULL DEFAULT '[]',
    avaliacao            INT,
    feedback             TEXT,
    data_primeira_resposta TIMESTAMPTZ,
    bot_pode_atender     BOOLEAN NOT NULL DEFAULT TRUE
);

ALTER TABLE oraculo_atendimento ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_atendimento FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_atendimento_tenant_isolation ON oraculo_atendimento
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_atendimento_tenant_status_dept   ON oraculo_atendimento (tenant_id, status, departamento_id);
CREATE INDEX oraculo_atendimento_tenant_dept_msg      ON oraculo_atendimento (tenant_id, departamento_id, data_ultima_mensagem);
CREATE INDEX oraculo_atendimento_tenant_atendente     ON oraculo_atendimento (tenant_id, atendente_humano_id, status);
CREATE INDEX oraculo_atendimento_tenant_etapa         ON oraculo_atendimento (tenant_id, etapa_atual_id, atendente_humano_id);

-- Mensagem: histórico completo inbound/outbound com suporte a mídias e citações
CREATE TABLE oraculo_mensagem (
    id                   SERIAL PRIMARY KEY,
    tenant_id            UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    atendimento_id       INT NOT NULL REFERENCES oraculo_atendimento(id) ON DELETE CASCADE,
    tipo                 VARCHAR(25) NOT NULL DEFAULT 'extendedTextMessage',
    conteudo             TEXT NOT NULL DEFAULT '',
    remetente            VARCHAR(20) NOT NULL DEFAULT 'contato',
    timestamp            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    message_id_whatsapp  VARCHAR(100),
    metadados            JSONB NOT NULL DEFAULT '{}',
    respondida           BOOLEAN NOT NULL DEFAULT FALSE,
    lido                 BOOLEAN NOT NULL DEFAULT FALSE,
    resposta_bot         TEXT,
    intent_detectado     JSONB NOT NULL DEFAULT '[]',
    entidades_extraidas  JSONB NOT NULL DEFAULT '[]',
    confianca_resposta   FLOAT,
    arquivo_midia        VARCHAR(255),
    analise_midia        TEXT,
    resumo_midia         TEXT,
    mensagem_citada_id   INT REFERENCES oraculo_mensagem(id) ON DELETE SET NULL,
    quoted_preview       JSONB,
    status_envio         VARCHAR(15) NOT NULL DEFAULT 'pending',
    data_entregue        TIMESTAMPTZ,
    data_lida            TIMESTAMPTZ
);

ALTER TABLE oraculo_mensagem ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_mensagem FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_mensagem_tenant_isolation ON oraculo_mensagem
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_mensagem_tenant_atend ON oraculo_mensagem (tenant_id, atendimento_id, timestamp);
CREATE INDEX oraculo_mensagem_lido         ON oraculo_mensagem (tenant_id, atendimento_id, lido);

-- MovimentoFluxo: histórico de transições Kanban para cálculo de SLAs
CREATE TABLE oraculo_movimento_fluxo (
    id                   SERIAL PRIMARY KEY,
    tenant_id            UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    atendimento_id       INT NOT NULL REFERENCES oraculo_atendimento(id) ON DELETE CASCADE,
    etapa_origem_id      INT REFERENCES oraculo_etapa_fluxo(id) ON DELETE SET NULL,
    etapa_destino_id     INT NOT NULL REFERENCES oraculo_etapa_fluxo(id) ON DELETE CASCADE,
    atendente_origem_id  INT REFERENCES oraculo_atendente(id) ON DELETE SET NULL,
    atendente_destino_id INT REFERENCES oraculo_atendente(id) ON DELETE SET NULL,
    motivo               TEXT,
    dados_complementares JSONB NOT NULL DEFAULT '{}',
    automatico           BOOLEAN NOT NULL DEFAULT FALSE,
    data_movimento       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    duracao_segundos     INT
);

ALTER TABLE oraculo_movimento_fluxo ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_movimento_fluxo FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_movimento_fluxo_tenant_isolation ON oraculo_movimento_fluxo
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_movimento_fluxo_tenant_atend ON oraculo_movimento_fluxo (tenant_id, atendimento_id, data_movimento DESC);
CREATE INDEX oraculo_movimento_fluxo_tenant_dest  ON oraculo_movimento_fluxo (tenant_id, etapa_destino_id, data_movimento DESC);

-- CampoPersonalizado: catálogo de campos dinâmicos para enriquecer atendimentos
CREATE TABLE atu_campo_personalizado (
    id                      BIGSERIAL PRIMARY KEY,
    tenant_id               UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    slug                    VARCHAR(120) NOT NULL,
    nome                    VARCHAR(120) NOT NULL,
    descricao               TEXT NOT NULL DEFAULT '',
    escopo                  VARCHAR(10) NOT NULL DEFAULT 'GLOBAL',
    fluxo_id                INT REFERENCES oraculo_fluxo_atendimento(id) ON DELETE SET NULL,
    tipo                    VARCHAR(20) NOT NULL DEFAULT 'texto',
    opcoes                  JSONB NOT NULL DEFAULT '[]',
    obrigatorio             BOOLEAN NOT NULL DEFAULT FALSE,
    extrair_automaticamente BOOLEAN NOT NULL DEFAULT TRUE,
    extrair_hint            VARCHAR(500) NOT NULL DEFAULT '',
    mostrar_no_card         BOOLEAN NOT NULL DEFAULT TRUE,
    ordem                   INT NOT NULL DEFAULT 0,
    ativo                   BOOLEAN NOT NULL DEFAULT TRUE,
    data_criacao            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_atualizacao        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, slug, escopo, fluxo_id)
);

ALTER TABLE atu_campo_personalizado ENABLE ROW LEVEL SECURITY;
ALTER TABLE atu_campo_personalizado FORCE  ROW LEVEL SECURITY;
CREATE POLICY atu_campo_personalizado_tenant_isolation ON atu_campo_personalizado
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX atu_campo_personalizado_tenant_escopo ON atu_campo_personalizado (tenant_id, escopo, fluxo_id, ativo);

-- ValorCampoAtendimento: valor preenchido de um campo dinâmico por atendimento
CREATE TABLE atu_valor_campo (
    id                BIGSERIAL PRIMARY KEY,
    tenant_id         UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    atendimento_id    INT NOT NULL REFERENCES oraculo_atendimento(id) ON DELETE CASCADE,
    campo_id          BIGINT NOT NULL REFERENCES atu_campo_personalizado(id) ON DELETE CASCADE,
    valor             JSONB NOT NULL,
    origem            VARCHAR(10) NOT NULL DEFAULT 'MANUAL',
    confianca         FLOAT,
    mensagem_origem_id INT REFERENCES oraculo_mensagem(id) ON DELETE SET NULL,
    editado_por_id    INT REFERENCES oraculo_atendente(id) ON DELETE SET NULL,
    data_atualizacao  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, atendimento_id, campo_id)
);

ALTER TABLE atu_valor_campo ENABLE ROW LEVEL SECURITY;
ALTER TABLE atu_valor_campo FORCE  ROW LEVEL SECURITY;
CREATE POLICY atu_valor_campo_tenant_isolation ON atu_valor_campo
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX atu_valor_campo_tenant_atend ON atu_valor_campo (tenant_id, atendimento_id, campo_id);

-- Etiqueta: catálogo de tags coloridas para conversas
CREATE TABLE atu_etiqueta (
    id           BIGSERIAL PRIMARY KEY,
    tenant_id    UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    nome         VARCHAR(50) NOT NULL,
    cor          VARCHAR(7) NOT NULL DEFAULT '#a98f71',
    descricao    VARCHAR(200) NOT NULL DEFAULT '',
    ativo        BOOLEAN NOT NULL DEFAULT TRUE,
    data_criacao TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, nome)
);

ALTER TABLE atu_etiqueta ENABLE ROW LEVEL SECURITY;
ALTER TABLE atu_etiqueta FORCE  ROW LEVEL SECURITY;
CREATE POLICY atu_etiqueta_tenant_isolation ON atu_etiqueta
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- EtiquetaAtendimento: M2M físico Atendimento <-> Etiqueta
CREATE TABLE atu_etiqueta_atendimento (
    id             BIGSERIAL PRIMARY KEY,
    tenant_id      UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    atendimento_id INT NOT NULL REFERENCES oraculo_atendimento(id) ON DELETE CASCADE,
    etiqueta_id    BIGINT NOT NULL REFERENCES atu_etiqueta(id) ON DELETE CASCADE,
    aplicada_em    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    aplicada_por_id INT REFERENCES oraculo_atendente(id) ON DELETE SET NULL,
    UNIQUE (tenant_id, atendimento_id, etiqueta_id)
);

ALTER TABLE atu_etiqueta_atendimento ENABLE ROW LEVEL SECURITY;
ALTER TABLE atu_etiqueta_atendimento FORCE  ROW LEVEL SECURITY;
CREATE POLICY atu_etiqueta_atendimento_tenant_isolation ON atu_etiqueta_atendimento
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX atu_etiqueta_atendimento_tenant_atend ON atu_etiqueta_atendimento (tenant_id, atendimento_id);

-- Nota: anotações internas do operador, invisíveis para o contato final
CREATE TABLE atu_nota (
    id             BIGSERIAL PRIMARY KEY,
    tenant_id      UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    atendimento_id INT NOT NULL REFERENCES oraculo_atendimento(id) ON DELETE CASCADE,
    texto          TEXT NOT NULL,
    criado_por_id  INT REFERENCES oraculo_atendente(id) ON DELETE SET NULL,
    criado_em      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE atu_nota ENABLE ROW LEVEL SECURITY;
ALTER TABLE atu_nota FORCE  ROW LEVEL SECURITY;
CREATE POLICY atu_nota_tenant_isolation ON atu_nota
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX atu_nota_tenant_atend ON atu_nota (tenant_id, atendimento_id, criado_em DESC);
