-- ============================================================
-- Módulo Clientes & Contatos: usuários finais do WhatsApp e clientes corporativos
-- ============================================================

-- Contato: usuário final do WhatsApp, identificado por telefone por tenant
CREATE TABLE oraculo_contato (
    id                      SERIAL PRIMARY KEY,
    tenant_id               UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    telefone                VARCHAR(20),
    nome_contato            VARCHAR(100),
    slug                    VARCHAR(120) NOT NULL DEFAULT '',
    email                   VARCHAR(254),
    nome_perfil_whatsapp    VARCHAR(100),
    data_cadastro           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ultima_interacao        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ativo                   BOOLEAN NOT NULL DEFAULT TRUE,
    metadados               JSONB NOT NULL DEFAULT '{}',
    foto_perfil             VARCHAR(255),
    foto_perfil_url_origem  VARCHAR(512),
    UNIQUE (tenant_id, telefone)
);

ALTER TABLE oraculo_contato ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_contato FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_contato_tenant_isolation ON oraculo_contato
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

CREATE INDEX oraculo_contato_tenant_telefone    ON oraculo_contato (tenant_id, telefone);
CREATE INDEX oraculo_contato_tenant_interacao   ON oraculo_contato (tenant_id, ultima_interacao DESC);

-- Cliente: cadastro formal de Pessoa Física ou Jurídica com dados fiscais
CREATE TABLE oraculo_cliente (
    id               SERIAL PRIMARY KEY,
    tenant_id        UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    nome_fantasia    VARCHAR(200) NOT NULL,
    slug             VARCHAR(220) NOT NULL DEFAULT '',
    razao_social     VARCHAR(200),
    tipo             VARCHAR(20),
    cnpj             VARCHAR(18),
    cpf              VARCHAR(14),
    telefone         VARCHAR(20),
    site             VARCHAR(200),
    ramo_atividade   VARCHAR(200),
    observacoes      TEXT,
    cep              VARCHAR(10),
    logradouro       VARCHAR(200),
    numero           VARCHAR(10),
    complemento      VARCHAR(100),
    bairro           VARCHAR(100),
    cidade           VARCHAR(100),
    uf               VARCHAR(2),
    pais             VARCHAR(50) DEFAULT 'Brasil',
    data_cadastro    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ultima_atualizacao TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ativo            BOOLEAN NOT NULL DEFAULT TRUE,
    metadados        JSONB NOT NULL DEFAULT '{}'
);

ALTER TABLE oraculo_cliente ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_cliente FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_cliente_tenant_isolation ON oraculo_cliente
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- Índices de unicidade parcial: CNPJ e CPF únicos por tenant quando preenchidos
CREATE UNIQUE INDEX oraculo_cliente_tenant_cnpj
    ON oraculo_cliente (tenant_id, cnpj)
    WHERE cnpj IS NOT NULL AND cnpj != '';

CREATE UNIQUE INDEX oraculo_cliente_tenant_cpf
    ON oraculo_cliente (tenant_id, cpf)
    WHERE cpf IS NOT NULL AND cpf != '';

CREATE INDEX oraculo_cliente_tenant_nome ON oraculo_cliente (tenant_id, nome_fantasia);

-- Tabela associativa M2M Clientes <-> Contatos
CREATE TABLE oraculo_cliente_contatos (
    id          SERIAL PRIMARY KEY,
    tenant_id   UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    cliente_id  INT NOT NULL REFERENCES oraculo_cliente(id) ON DELETE CASCADE,
    contato_id  INT NOT NULL REFERENCES oraculo_contato(id) ON DELETE CASCADE,
    UNIQUE (cliente_id, contato_id)
);

ALTER TABLE oraculo_cliente_contatos ENABLE ROW LEVEL SECURITY;
ALTER TABLE oraculo_cliente_contatos FORCE  ROW LEVEL SECURITY;
CREATE POLICY oraculo_cliente_contatos_tenant_isolation ON oraculo_cliente_contatos
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);
