-- ============================================================
-- N13.2 — Consentimentos OAuth 2.1 dos clientes MCP
-- ============================================================
--
-- Registro de "este usuário autorizou este cliente MCP a operar o tenant dele".
-- É a linha que a tela "Aplicativos conectados" (N13.8) lista e revoga, e é
-- também o que permite invalidar um refresh token na hora, sem esperar o `exp`.
--
-- O que NÃO mora aqui:
--   · o access token — é um JWT de ~15 min, não persistido em lugar nenhum;
--   · o código de autorização — vive no Redis com TTL de ~60s e consumo atômico
--     (GETDEL), porque replay de código é a falha clássica de um AS caseiro e
--     uso único é mais fácil de garantir num GETDEL do que numa transação;
--   · o refresh token em claro — só o hash SHA-256, rotacionado a cada uso.
--
-- Revogação é SOFT (`revoked_at`): a trilha de auditoria referencia `grant_id`,
-- e apagar a linha deixaria o audit_log apontando para o nada.

CREATE TABLE mcp_oauth_grant (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id           UUID NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    user_id             INT  NOT NULL REFERENCES auth_user(id)      ON DELETE CASCADE,

    -- O `client_id` do OAuth é a URL do Client ID Metadata Document (CIMD). Não
    -- há registro prévio de cliente (DCR foi deprecado pela spec MCP): a
    -- identidade do cliente É a URL, e o documento buscado nela declara nome e
    -- redirect_uris. Por isso é TEXT e não FK para uma tabela de aplicativos.
    client_id           TEXT NOT NULL,

    -- Nome exibido, copiado do CIMD no momento do consentimento. É TEXTO DE
    -- TERCEIRO: escapar ao renderizar e limitar tamanho ao persistir (o CHECK
    -- abaixo faz a segunda metade). Guardar em vez de rebuscar mantém a tela
    -- honesta sobre o que o usuário viu quando aprovou, mesmo que o documento
    -- remoto mude depois.
    client_name         TEXT NOT NULL,

    -- O redirect_uri exato usado na autorização, para a trilha. A validação por
    -- igualdade exata acontece no AS; aqui é registro histórico.
    redirect_uri        TEXT NOT NULL,

    -- Escopos concedidos no consentimento (array JSON de strings do catálogo
    -- canônico — doc 09 §3). Na emissão de cada access token estes escopos são
    -- re-interseccionados com os escopos ATUAIS do usuário: rebaixar alguém no
    -- painel encolhe o token dele na renovação seguinte, sem tocar no grant.
    scopes              JSONB NOT NULL DEFAULT '[]',

    -- SHA-256 do segredo do refresh token corrente. Rotacionado a cada uso; NULL
    -- quando o grant ainda não emitiu refresh ou depois de revogado.
    --
    -- SHA-256 e não argon2id (o plano dizia argon2id): o refresh token é um
    -- segredo de 256 bits gerado por CSPRNG, não uma senha escolhida por gente.
    -- Argon2 existe para tornar caro o ataque de dicionário a segredo de baixa
    -- entropia — contra 256 bits aleatórios não há dicionário, e o custo (~100ms
    -- de CPU por renovação) seria pago em todo refresh, por todo agente. É também
    -- o que `application::tokens::hash_refresh_token` já faz com os refresh
    -- tokens do painel: uma segunda convenção aqui só criaria divergência.
    refresh_token_hash  TEXT,

    last_used_at        TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_ip          INET,

    CONSTRAINT mcp_oauth_grant_client_id_tamanho   CHECK (char_length(client_id) <= 2048),
    CONSTRAINT mcp_oauth_grant_client_name_tamanho CHECK (char_length(client_name) <= 200),
    CONSTRAINT mcp_oauth_grant_redirect_tamanho    CHECK (char_length(redirect_uri) <= 2048)
);

ALTER TABLE mcp_oauth_grant ENABLE ROW LEVEL SECURITY;
ALTER TABLE mcp_oauth_grant FORCE  ROW LEVEL SECURITY;
CREATE POLICY mcp_oauth_grant_tenant_isolation ON mcp_oauth_grant
    FOR ALL
    USING (tenant_id = NULLIF(current_setting('app.current_tenant', true), '')::uuid);

-- A consulta quente é "os grants deste usuário" (tela de aplicativos conectados)
-- e "existe grant deste usuário para este cliente?" (reconsentimento).
CREATE INDEX mcp_oauth_grant_user_client ON mcp_oauth_grant (user_id, client_id);

-- Validação de refresh token: a busca entra pelo hash. Parcial porque grant
-- revogado ou sem refresh nunca é alvo dessa consulta.
CREATE INDEX mcp_oauth_grant_refresh_hash ON mcp_oauth_grant (refresh_token_hash)
    WHERE refresh_token_hash IS NOT NULL AND revoked_at IS NULL;

COMMENT ON TABLE  mcp_oauth_grant IS
    'Consentimento OAuth 2.1 de um usuário a um cliente MCP externo (Claude, ChatGPT, Cursor).';
COMMENT ON COLUMN mcp_oauth_grant.client_id IS
    'URL do Client ID Metadata Document — é o identificador do cliente na spec MCP (DCR deprecado).';
COMMENT ON COLUMN mcp_oauth_grant.refresh_token_hash IS
    'SHA-256 do segredo do refresh corrente. Rotacionado a cada uso; apresentar um hash antigo derruba o grant.';
COMMENT ON COLUMN mcp_oauth_grant.revoked_at IS
    'Revogação soft: a trilha de auditoria referencia grant_id e precisa sobreviver à revogação.';
