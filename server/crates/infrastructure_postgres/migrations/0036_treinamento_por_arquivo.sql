-- B9 (N10 E5) — treinamento por upload de arquivo.
--
-- O binário não passa pelo banco nem pelo gRPC: o cliente sobe direto ao R2 e o
-- treinamento guarda só o ponteiro. O texto é extraído depois, por um job do
-- scheduler, e cai em `conteudo` — a partir daí segue o ciclo de sempre
-- (revisão → finalizar → vetorizar).
--
-- `extracao_status`: NULL para treinamento de texto colado (não há o que
-- extrair); 'pendente' até o job rodar; 'extraido' ou 'falhou'. `extracao_erro`
-- guarda o motivo pronto para quem treina ler — nunca o texto do documento.
ALTER TABLE oraculo_treinamento
    ADD COLUMN IF NOT EXISTS arquivo_chave    TEXT,
    ADD COLUMN IF NOT EXISTS arquivo_nome     VARCHAR(255),
    ADD COLUMN IF NOT EXISTS arquivo_mimetype VARCHAR(120),
    ADD COLUMN IF NOT EXISTS arquivo_bytes    BIGINT,
    ADD COLUMN IF NOT EXISTS extracao_status  VARCHAR(12),
    ADD COLUMN IF NOT EXISTS extracao_erro    TEXT;

-- A fila do job: só os pendentes, em ordem de chegada.
CREATE INDEX IF NOT EXISTS oraculo_treinamento_extracao_pendente
    ON oraculo_treinamento (data_criacao)
    WHERE extracao_status = 'pendente';
