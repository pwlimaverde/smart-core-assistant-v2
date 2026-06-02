-- ============================================================
-- Módulo Settings: configurações dinâmicas globais (CoreSettings)
-- Substitui o Firebase Remote Config do legado.
-- Tabela GLOBAL, sem RLS — visível para toda a aplicação.
-- ============================================================

CREATE TABLE settings_manager_coresettings (
    id          SERIAL PRIMARY KEY,
    key         VARCHAR(255) NOT NULL UNIQUE,
    value       TEXT NOT NULL,
    encrypted   BOOLEAN NOT NULL DEFAULT FALSE,
    description TEXT NOT NULL DEFAULT '',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Sem RLS: CoreSettings são globais do sistema, acessadas apenas pelo backend.
-- Invalidação de cache via Redis Pub/Sub (canal core:settings:invalidate) — fase futura.

-- Dados iniciais obrigatórios: chaves de fallback globais do sistema
INSERT INTO settings_manager_coresettings (key, value, description) VALUES
    ('MSG_FALLBACK',             'Ops, tive um problema ao processar sua mensagem. Pode repetir?',
     'Mensagem padrão de erro de processamento do bot.'),
    ('MSG_SEM_INFO',             'Não encontrei informações suficientes para responder. Um atendente irá ajudá-lo.',
     'Mensagem quando o RAG não retorna resultado útil.'),
    ('MSG_TRANSFERENCIA',        'Aguarde um momento, estou transferindo para um de nossos atendentes.',
     'Mensagem de aviso de transferência para humano.'),
    ('LLM_CLASS',                'ChatOpenAI',
     'Classe padrão do LLM (ex: ChatOpenAI, ChatGroq).'),
    ('MODEL',                    'gpt-4o-mini',
     'Modelo padrão do LLM.'),
    ('LLM_TEMPERATURE',          '0.7',
     'Temperatura padrão do LLM.'),
    ('TRANSCRIPTION_PROVIDER',   'openai',
     'Provedor padrão de transcrição de áudio.'),
    ('TRANSCRIPTION_MODEL',      'whisper-1',
     'Modelo padrão de transcrição.'),
    ('VISION_PROVIDER',          'openai',
     'Provedor padrão de visão computacional.'),
    ('VISION_MODEL',             'gpt-4o',
     'Modelo padrão de visão.'),
    ('EMBEDDINGS_CLASS',         'OpenAIEmbeddings',
     'Classe padrão de embeddings.'),
    ('EMBEDDINGS_MODEL',         'text-embedding-3-small',
     'Modelo padrão de embeddings.'),
    ('CHUNK_SIZE',               '1000',
     'Tamanho padrão de chunk para RAG.'),
    ('CHUNK_OVERLAP',            '200',
     'Sobreposição padrão entre chunks.'),
    ('SIMILARITY_THRESHOLD',     '0.40',
     'Limiar mínimo de similaridade para intenções.'),
    ('VECTOR_DISTANCE_THRESHOLD','0.25',
     'Limiar máximo de distância de cosseno para pgvector.'),
    ('OPENAI_API_KEY',           '',
     'Chave global da OpenAI (sobrescrita por chave local do tenant).'),
    ('GROQ_API_KEY',             '',
     'Chave global da Groq.'),
    ('GOOGLE_API_KEY',           '',
     'Chave global do Google (Gemini/Vision).')
ON CONFLICT (key) DO NOTHING;
