-- ============================================================
-- Módulo Operacional: departamentos, fluxos Kanban, atendentes e instâncias
-- Ordem por dependência de FK: departamento → fluxo → etapa → atendente → app_instance
-- ============================================================

-- Departamento: divisão operacional ou setor comercial do tenant
CREATE TABLE oraculo_departamento (
    id                  SERIAL PRIMARY KEY,
    tenant_id           UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    nome                VARCHAR(100) NOT NULL,
    slug                VARCHAR(120) NOT NULL DEFAULT '',
    descricao           TEXT,
    ativo               BOOLEAN NOT NULL DEFAULT TRUE,
    telefone_instancia  VARCHAR(20),
    api_key             VARCHAR(100),
    configuracoes       JSONB NOT NULL DEFAULT '{}',
    metadados           JSONB NOT NULL DEFAULT '{}',
    data_criacao        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, nome),
    UNIQUE (tenant_id, slug)
);

ALTER TABLE oraculo_departamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_departamento FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_departamento_tenant_isolation ON oraculo_departamento
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_departamento_tenant_slug       ON oraculo_departamento (tenant_id, slug);
CREATE INDEX oraculo_departamento_tenant_ativo_nome ON oraculo_departamento (tenant_id, ativo, nome);

-- FluxoAtendimento: quadro Kanban personalizado por departamento
CREATE TABLE oraculo_fluxo_atendimento (
    id               SERIAL PRIMARY KEY,
    tenant_id        UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    departamento_id  INT NOT NULL REFERENCES oraculo_departamento(id) ON DELETE CASCADE,
    nome             VARCHAR(100) NOT NULL,
    descricao        TEXT,
    ativo            BOOLEAN NOT NULL DEFAULT TRUE,
    data_criacao     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    data_atualizacao TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE oraculo_fluxo_atendimento ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_fluxo_atendimento FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_fluxo_atendimento_tenant_isolation ON oraculo_fluxo_atendimento
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_fluxo_atendimento_tenant_dept ON oraculo_fluxo_atendimento (tenant_id, departamento_id);

-- EtapaFluxo: coluna física no Kanban — cada atendimento reside em uma etapa
CREATE TABLE oraculo_etapa_fluxo (
    id                  SERIAL PRIMARY KEY,
    tenant_id           UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    fluxo_id            INT NOT NULL REFERENCES oraculo_fluxo_atendimento(id) ON DELETE CASCADE,
    nome                VARCHAR(50) NOT NULL,
    descricao           VARCHAR(200),
    ordem               INT NOT NULL,
    cor                 VARCHAR(7)  NOT NULL DEFAULT '#6B7280',
    tipo_etapa          VARCHAR(20) NOT NULL DEFAULT 'trabalho',
    permite_atribuicao  BOOLEAN NOT NULL DEFAULT TRUE,
    automatico          BOOLEAN NOT NULL DEFAULT FALSE,
    regras_transicao    JSONB NOT NULL DEFAULT '{}',
    campos_obrigatorios JSONB NOT NULL DEFAULT '[]',
    ativo               BOOLEAN NOT NULL DEFAULT TRUE,
    data_criacao        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (fluxo_id, ordem)
);

ALTER TABLE oraculo_etapa_fluxo ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_etapa_fluxo FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_etapa_fluxo_tenant_isolation ON oraculo_etapa_fluxo
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_etapa_fluxo_tenant_ordem ON oraculo_etapa_fluxo (tenant_id, fluxo_id, ordem);
CREATE INDEX oraculo_etapa_fluxo_tenant_tipo  ON oraculo_etapa_fluxo (tenant_id, tipo_etapa);
CREATE INDEX oraculo_etapa_fluxo_tenant_ativo ON oraculo_etapa_fluxo (tenant_id, ativo);

-- Atendente: operador humano que atende chats no painel
-- usuario_id é FK lógica (sem db_constraint) para compatibilidade cross-banco do legado
CREATE TABLE oraculo_atendente (
    id                          SERIAL PRIMARY KEY,
    tenant_id                   UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    nome                        VARCHAR(100) NOT NULL,
    slug                        VARCHAR(120) NOT NULL DEFAULT '',
    telefone                    VARCHAR(20),
    cargo                       VARCHAR(100) NOT NULL DEFAULT '',
    email                       VARCHAR(254) NOT NULL,
    departamento_id             INT REFERENCES oraculo_departamento(id) ON DELETE SET NULL,
    fluxo_id                    INT NOT NULL REFERENCES oraculo_fluxo_atendimento(id) ON DELETE RESTRICT,
    usuario_id                  INT,   -- FK lógica para auth_user; sem db_constraint
    usuario_sistema             VARCHAR(50),
    ativo                       BOOLEAN NOT NULL DEFAULT TRUE,
    disponivel                  BOOLEAN NOT NULL DEFAULT TRUE,
    max_atendimentos_simultaneos INT NOT NULL DEFAULT 5,
    data_ultima_atribuicao      TIMESTAMPTZ,
    horario_trabalho            JSONB NOT NULL DEFAULT '{}',
    especialidades              JSONB NOT NULL DEFAULT '[]',
    metadados                   JSONB NOT NULL DEFAULT '{}',
    data_cadastro               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ultima_atividade            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, email)
);

ALTER TABLE oraculo_atendente ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_atendente FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_atendente_tenant_isolation ON oraculo_atendente
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE UNIQUE INDEX oraculo_atendente_tenant_telefone
    ON oraculo_atendente (tenant_id, telefone)
    WHERE telefone IS NOT NULL AND telefone != '';

CREATE INDEX oraculo_atendente_tenant_dept_disp    ON oraculo_atendente (tenant_id, departamento_id, disponivel);
CREATE INDEX oraculo_atendente_tenant_disp_max     ON oraculo_atendente (tenant_id, disponivel, max_atendimentos_simultaneos);
CREATE INDEX oraculo_atendente_tenant_last_assign  ON oraculo_atendente (tenant_id, data_ultima_atribuicao);
CREATE INDEX oraculo_atendente_tenant_fluxo        ON oraculo_atendente (tenant_id, fluxo_id);

-- AppInstance: instância de canal WhatsApp conectada à Evolution API centralizada
CREATE TABLE oraculo_app_instance (
    id              SERIAL PRIMARY KEY,
    tenant_id       UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    api_key         VARCHAR(128) NOT NULL UNIQUE,
    channel         VARCHAR(32) NOT NULL,
    display_name    VARCHAR(100),
    departamento_id INT REFERENCES oraculo_departamento(id) ON DELETE SET NULL,
    owner_id        INT UNIQUE REFERENCES oraculo_atendente(id) ON DELETE SET NULL,
    active          BOOLEAN NOT NULL DEFAULT TRUE,
    resposta_bot    BOOLEAN NOT NULL DEFAULT TRUE,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE oraculo_app_instance ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_app_instance FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_app_instance_tenant_isolation ON oraculo_app_instance
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_app_instance_tenant_api_key ON oraculo_app_instance (tenant_id, api_key);
CREATE INDEX oraculo_app_instance_tenant_channel ON oraculo_app_instance (tenant_id, channel);
CREATE INDEX oraculo_app_instance_tenant_dept    ON oraculo_app_instance (tenant_id, departamento_id);
