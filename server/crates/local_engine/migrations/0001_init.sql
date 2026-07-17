-- Índice local (SQLite) do local_engine — leitura rápida offline no desktop do
-- atendente. Espelha o suficiente de AtendimentoResumo/MensagemThread do módulo
-- operacional. Datas em epoch-millis (INTEGER) para casar com a borda gRPC.

CREATE TABLE IF NOT EXISTS atendimentos (
    id                    INTEGER PRIMARY KEY,
    contato_id            INTEGER NOT NULL,
    status                TEXT    NOT NULL,
    departamento_id       INTEGER,
    fluxo_atendimento_id  INTEGER,
    etapa_atual_id        INTEGER,
    assunto               TEXT    NOT NULL,
    prioridade            TEXT    NOT NULL,
    atendente_humano_id   INTEGER,
    data_inicio           INTEGER NOT NULL,
    data_ultima_mensagem  INTEGER
);

CREATE INDEX IF NOT EXISTS idx_atendimentos_status
    ON atendimentos (status, departamento_id);

CREATE TABLE IF NOT EXISTS mensagens (
    id             INTEGER PRIMARY KEY,
    atendimento_id INTEGER NOT NULL,
    tipo           TEXT    NOT NULL,
    conteudo       TEXT    NOT NULL,
    remetente      TEXT    NOT NULL,
    timestamp      INTEGER NOT NULL,
    status_envio   TEXT    NOT NULL,
    gerado_por_ia  INTEGER NOT NULL DEFAULT 0,
    resumo_midia   TEXT
);

CREATE INDEX IF NOT EXISTS idx_mensagens_atendimento
    ON mensagens (atendimento_id, timestamp);

-- Fila de ações offline do atendente. `id` é um uuid v7 gerado no cliente (chave
-- de idempotência levada ao servidor); `version` é o contador monotônico usado
-- na resolução last-write-wins ao sincronizar.
CREATE TABLE IF NOT EXISTS offline_actions (
    id             TEXT    PRIMARY KEY,
    version        INTEGER NOT NULL,
    atendimento_id INTEGER NOT NULL,
    kind           TEXT    NOT NULL,
    payload        TEXT    NOT NULL,
    created_at     INTEGER NOT NULL,
    synced         INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_offline_actions_pendentes
    ON offline_actions (synced, version);
