-- N8: fecha o gap encontrado na fase de migracao/cutover — whatsapp_instance.api_key
-- ja tinha o comentario "encriptado em repouso" desde a 0008, mas o adapter Rust
-- nunca chamou CipherManager (gravava/lia String plana). Agora a coluna passa a
-- guardar o jsonb {ciphertext,nonce,tag} do AES-256-GCM (mesmo padrao de
-- tenants_tenantconfig.api_keys), decifrado em memoria pelo adapter.
--
-- Sem backfill: ainda nao ha dados reais de producao nesta tabela (achado da fase
-- N8, confirmado ao ler o schema atual). Linhas pre-existentes (ambiente de teste)
-- viram jsonb vazio '{}' — CipherManager::decrypt_json_entry trata isso como
-- string vazia, sem quebrar. Se este assumption deixar de valer (dados reais já
-- migrados antes de aplicar esta migration), é preciso recifrar as linhas
-- existentes antes do ALTER, não depois.
ALTER TABLE whatsapp_instance
    ALTER COLUMN api_key TYPE JSONB USING '{}'::jsonb,
    ALTER COLUMN api_key SET DEFAULT '{}'::jsonb;

COMMENT ON COLUMN whatsapp_instance.api_key IS 'Token de autenticação da instância — cifrado em repouso (AES-256-GCM via CipherManager, jsonb {ciphertext,nonce,tag})';
