-- Prompts de sistema configuráveis pela mesma cascata Tenant > CoreSettings.
--
-- Até aqui os prompts do bot viviam como constantes no código do `ia_engine`
-- (`_SYSTEM_PROMPT` de cada datasource, `_MSG_TRANSFERENCIA_GENERICA`), enquanto
-- a v1 os mantinha no banco (`settings_manager_coresettings`, chaves `prompt_*`)
-- e permitia ajustá-los sem release. Esta migration devolve essa capacidade,
-- sem repetir o desenho da v1: em vez de uma coluna por prompt, um único JSONB
-- de overrides por tenant sobre as chaves globais — o mesmo espírito de
-- `api_keys`, e extensível a um prompt novo sem migration.
--
-- Precedência (idêntica à dos demais campos):
--   tenants_tenantconfig.prompts->>'CHAVE'  >  coresettings['CHAVE']  >  default no código
--
-- O default no código é deliberado e é o último elo: a IA não pode parar de
-- responder porque uma chave não foi semeada.
ALTER TABLE tenants_tenantconfig
    ADD COLUMN IF NOT EXISTS prompts JSONB NOT NULL DEFAULT '{}';

COMMENT ON COLUMN tenants_tenantconfig.prompts IS
    'Overrides de prompt deste tenant (chave => texto). Chave ausente herda o CoreSetting PROMPT_* global; ausente lá também, usa o default versionado no ia_engine.';

-- Chaves globais. Valor vazio = "sem override": o ia_engine cai no default do
-- código. Semear vazio (em vez de duplicar aqui o texto dos prompts) evita duas
-- fontes de verdade divergindo em silêncio — o texto canônico é o do código, e
-- só quem edita pelo painel passa a ter valor aqui.
--
-- Os valores REAIS da v1 entram por cima destas linhas, via ETL
-- (`infra/migracao-v1`, entidade settings.coresettings, que faz DO UPDATE).
INSERT INTO settings_manager_coresettings (key, value, description) VALUES
    ('PROMPT_SYSTEM_ANALISE_PREVIA_MENSAGEM', '',
     'Prompt de sistema da análise prévia (intenções/entidades). Vazio = default do ia_engine.'),
    ('PROMPT_HUMAN_ANALISE_PREVIA_MENSAGEM', '',
     'Turno humano da análise prévia. Vazio = default do ia_engine.'),
    ('PROMPT_INTENT_SYSTEM', '',
     'Bloco de instruções de intenção na análise prévia. Vazio = default do ia_engine.'),
    ('PROMPT_INTENT_FOOTER', '',
     'Rodapé de instruções de intenção na análise prévia. Vazio = default do ia_engine.'),
    ('PROMPT_REGRAS_RESPOSTA', '',
     'Regras de resposta do bot (bloco do prompt de sistema do Responder). Vazio = default do ia_engine.'),
    ('PROMPT_REGRAS_TRANSFERENCIA', '',
     'Regras de transferência para atendente humano. Vazio = default do ia_engine.'),
    ('PROMPT_TEMPLATE_USER_RAG', '',
     'Template do turno do usuário com histórico e contexto RAG. Vazio = default do ia_engine.'),
    ('PROMPT_SENTIMENTO_SYSTEM', '',
     'Prompt de sistema da análise de sentimento/avaliação. Vazio = default do ia_engine.'),
    ('PROMPT_INTERPRET_MEDIA_IMAGE', '',
     'Prompt de interpretação de imagem. Vazio = default do ia_engine.'),
    ('PROMPT_INTERPRET_MEDIA_VIDEO', '',
     'Prompt de interpretação de vídeo. Vazio = default do ia_engine.'),
    ('PROMPT_INTERPRET_MEDIA_DOCUMENT', '',
     'Prompt de extração de conteúdo de documento. Vazio = default do ia_engine.'),
    ('PROMPT_TRANSCRIBE_RESUMO', '',
     'Prompt do resumo da transcrição de áudio. Vazio = default do ia_engine.'),
    -- As duas abaixo vêm da v1 e ainda NÃO têm consumidor na v2: as features de
    -- curadoria de conteúdo de treinamento (pré-análise e melhoria do texto antes
    -- de virar documento do RAG) não foram implementadas. Semeadas para o ETL ter
    -- onde pousar os valores da v1 sem perdê-los.
    ('PROMPT_SYSTEM_ANALISE_CONTEUDO', '',
     'v1: pré-análise de conteúdo de treinamento. SEM consumidor na v2 (feature não implementada).'),
    ('PROMPT_HUMAN_ANALISE_CONTEUDO', '',
     'v1: turno humano da pré-análise de conteúdo. SEM consumidor na v2 (feature não implementada).'),
    ('PROMPT_SYSTEM_MELHORIA_CONTEUDO', '',
     'v1: melhoria de conteúdo de treinamento. SEM consumidor na v2 (feature não implementada).'),
    ('PROMPT_HUMAN_MELHORIA_CONTEUDO', '',
     'v1: turno humano da melhoria de conteúdo. SEM consumidor na v2 (feature não implementada).')
ON CONFLICT (key) DO NOTHING;
