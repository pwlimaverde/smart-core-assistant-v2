-- N8.5/E3 — fechar o ciclo da pesquisa de satisfação.
--
-- O defeito: `oraculo_atendimento.avaliacao` e `.feedback` existem desde a 0006 e
-- só aparecem em SELECT. Ninguém nunca PEDIU a nota ao contato — mas o scheduler
-- roda `processar_feedback_vencido` e marca como "feedback expirado" todo
-- atendimento resolvido com `avaliacao IS NULL`. Ou seja: a v2 expira uma
-- pesquisa que jamais foi solicitada.
--
-- Sem a coluna abaixo não há como distinguir "o cliente não respondeu" de "nunca
-- foi perguntado", que é exatamente o que torna o bug invisível no relatório.

ALTER TABLE oraculo_atendimento
    ADD COLUMN IF NOT EXISTS feedback_solicitado_em TIMESTAMPTZ;

COMMENT ON COLUMN oraculo_atendimento.feedback_solicitado_em IS
    'Quando a pesquisa de satisfação foi enviada ao contato. NULL = nunca solicitada — o expirador de feedback deve ignorar essas linhas.';

-- O expirador varre por status + ausência de avaliação; com a coluna nova ele
-- passa a exigir solicitação prévia. Índice parcial cobre exatamente essa varredura.
CREATE INDEX IF NOT EXISTS idx_atendimento_feedback_pendente
    ON oraculo_atendimento (tenant_id, feedback_solicitado_em)
    WHERE feedback_solicitado_em IS NOT NULL AND avaliacao IS NULL;

-- Texto e liga/desliga da pesquisa, por tenant, com cascata Tenant > CoreSettings.
--
-- A v1 tinha o texto FIXO no código, com o nome de uma empresa dentro
-- ("Ecoprint") — funcionava num sistema de cliente único e não sobrevive a
-- multi-tenant. Aqui cada tenant escreve o próprio pedido de avaliação.
ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS msg_pesquisa_satisfacao VARCHAR(500);

ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS pesquisa_satisfacao_ativa BOOLEAN;

COMMENT ON COLUMN tenants_tenantconfig.msg_pesquisa_satisfacao IS
    'Texto enviado ao contato ao encerrar o atendimento, pedindo nota de 1 a 5; NULL/vazio herda o CoreSetting MSG_PESQUISA_SATISFACAO.';

COMMENT ON COLUMN tenants_tenantconfig.pesquisa_satisfacao_ativa IS
    'Liga a pesquisa de satisfação para este tenant; NULL herda o CoreSetting PESQUISA_SATISFACAO_ATIVA.';

INSERT INTO settings_manager_coresettings (key, value, description) VALUES
    ('MSG_PESQUISA_SATISFACAO',
     'Seu atendimento foi encerrado. Que nota de 1 a 5 você dá para o atendimento que recebeu? Se quiser, escreva também o que achou.',
     'Texto padrão do pedido de avaliação enviado ao encerrar um atendimento; sobreposto por tenants_tenantconfig.msg_pesquisa_satisfacao.'),
    ('PESQUISA_SATISFACAO_ATIVA', 'true',
     'Padrão global da pesquisa de satisfação ao encerrar atendimento; sobreposto por tenants_tenantconfig.pesquisa_satisfacao_ativa.')
ON CONFLICT (key) DO NOTHING;
