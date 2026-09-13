-- N11 E8 — recuperação de senha.
--
-- Guarda o HASH do token (SHA-256, hex), nunca o token: quem lê o banco não
-- consegue trocar a senha de ninguém. O token em claro existe só no e-mail.
--
-- Uso único por `used_at`, e não por DELETE: a linha consumida fica como
-- registro de que houve uma troca, e o índice parcial mantém barata a busca
-- pelos pedidos ainda válidos.
--
-- Sem RLS: `auth_user` é global (o usuário existe antes e acima do tenant), e a
-- redefinição acontece sem sessão. Os GRANTs vêm dos default privileges da
-- 0016 e da 0018.
CREATE TABLE IF NOT EXISTS auth_password_reset (
    id          BIGSERIAL PRIMARY KEY,
    user_id     INT NOT NULL REFERENCES auth_user(id) ON DELETE CASCADE,
    token_hash  CHAR(64) NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_auth_password_reset_pendente
    ON auth_password_reset (user_id)
    WHERE used_at IS NULL;
