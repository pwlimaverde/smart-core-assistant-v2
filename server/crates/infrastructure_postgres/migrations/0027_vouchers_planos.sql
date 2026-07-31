-- ============================================================
-- Vouchers de ativação + limite de fluxos no plano
-- ============================================================
--
-- Até aqui, um tenant só nascia pela mão do superusuário (`CreateTenant`). O
-- cadastro pela própria aplicação exige um portão de ativação: alguém que baixou
-- o app precisa comprovar o pagamento antes de a conta valer. O gateway ainda
-- não foi escolhido, então o primeiro (e por ora único) meio de pagamento é o
-- VOUCHER — um código que confirma a assinatura na hora.
--
-- O voucher NÃO é cupom de desconto: ele não abate valor, ele concede um plano
-- por um período. Quando um gateway real entrar, será outro provedor da mesma
-- porta de pagamento, gravando na mesma `tenants_subscription`.

-- ------------------------------------------------------------
-- Limite de fluxos por plano
-- ------------------------------------------------------------
-- Acompanha `max_instances`/`max_departments` (0003). O default 1 é conservador:
-- planos já existentes não ganham folga silenciosamente.
ALTER TABLE tenants_plan
    ADD COLUMN IF NOT EXISTS max_fluxos INT NOT NULL DEFAULT 1;

COMMENT ON COLUMN tenants_plan.max_fluxos IS
    'Máximo de fluxos de atendimento (Kanban) ativos para tenants neste plano.';

-- ------------------------------------------------------------
-- Voucher: código de ativação de assinatura
-- ------------------------------------------------------------
-- Sem RLS, como `tenants_plan`: é catálogo global do SaaS, não dado de tenant.
-- Quem pode ler/escrever é decidido na borda (rotas de superusuário).
CREATE TABLE tenants_voucher (
    id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- `codigo` guarda a grafia original (para exibir no painel); a busca e a
    -- unicidade usam `codigo_normalizado` (UPPER+TRIM), para que "DevTeste",
    -- "devteste " e "DEVTESTE" sejam o mesmo voucher e não possam coexistir.
    codigo             VARCHAR(64) NOT NULL,
    codigo_normalizado VARCHAR(64) NOT NULL UNIQUE,
    descricao          TEXT        NOT NULL DEFAULT '',
    plan_id            INT         NOT NULL REFERENCES tenants_plan(id) ON DELETE RESTRICT,
    -- Duração da assinatura concedida, a contar do resgate (180 = ~6 meses).
    duracao_dias       INT         NOT NULL,
    -- 0 = ilimitado. Campanha aberta usa 0; código nominal usa 1.
    max_resgates       INT         NOT NULL DEFAULT 1,
    resgates_usados    INT         NOT NULL DEFAULT 0,
    valido_de          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- NULL = não expira sozinho (só por revogação ou esgotamento).
    valido_ate         TIMESTAMPTZ,
    -- Revogação é o desligamento manual: bloqueia NOVOS resgates e não toca nas
    -- assinaturas já concedidas (revogar um código não rescinde contrato firmado).
    -- Para encerrar uma conta específica existe `SetTenantActive`.
    revogado_em        TIMESTAMPTZ,
    revogado_por_id    INT         REFERENCES auth_user(id) ON DELETE SET NULL,
    motivo_revogacao   TEXT        NOT NULL DEFAULT '',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by_id      INT         REFERENCES auth_user(id) ON DELETE SET NULL,

    CONSTRAINT tenants_voucher_duracao_positiva  CHECK (duracao_dias > 0),
    CONSTRAINT tenants_voucher_resgates_validos  CHECK (max_resgates >= 0 AND resgates_usados >= 0),
    CONSTRAINT tenants_voucher_janela_coerente   CHECK (valido_ate IS NULL OR valido_ate > valido_de)
);

COMMENT ON TABLE tenants_voucher IS
    'Códigos de ativação de assinatura (meio de pagamento, não cupom de desconto).';
COMMENT ON COLUMN tenants_voucher.codigo_normalizado IS
    'UPPER(TRIM(codigo)) — chave de busca no resgate e garantia de unicidade case-insensitive.';
COMMENT ON COLUMN tenants_voucher.max_resgates IS
    '0 = ilimitado. O resgate compara `resgates_usados < max_resgates` no mesmo UPDATE que incrementa.';

-- O resgate filtra por código normalizado; o índice vem do UNIQUE. Este aqui
-- serve à listagem do painel, que ordena por criação.
CREATE INDEX tenants_voucher_created ON tenants_voucher (created_at DESC);

-- ------------------------------------------------------------
-- Resgate: quem usou qual voucher, e o que recebeu
-- ------------------------------------------------------------
-- Sem RLS, apesar de ter `tenant_id`: esta é a contraparte do voucher (registro
-- do SaaS sobre uma concessão), não dado operacional do tenant, e quem a lê é o
-- superusuário em contexto cross-tenant. Com FORCE RLS a leitura do painel
-- exigiria pool com BYPASSRLS e falharia calada — o mesmo tropeço que o pre-warm
-- de config já custou. Se um dia o próprio tenant precisar ver o seu resgate,
-- aí sim entra policy.
--
-- Existe por dois motivos: auditoria (o painel mostra o histórico do voucher) e
-- IDEMPOTÊNCIA. O `UPDATE ... RETURNING` do resgate já é atômico e resolve a
-- corrida entre dois cadastros simultâneos, mas não impede que uma RETENTATIVA
-- de rede do mesmo cadastro consuma o código duas vezes. A UNIQUE abaixo impede:
-- o segundo INSERT falha e a transação inteira volta atrás, devolvendo o resgate.
CREATE TABLE tenants_voucher_redemption (
    id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    voucher_id     UUID        NOT NULL REFERENCES tenants_voucher(id) ON DELETE CASCADE,
    tenant_id      UUID        NOT NULL REFERENCES tenants_tenant(id) ON DELETE CASCADE,
    plan_id        INT         NOT NULL REFERENCES tenants_plan(id),
    periodo_inicio TIMESTAMPTZ NOT NULL,
    periodo_fim    TIMESTAMPTZ NOT NULL,
    -- Origem da tentativa, para investigar abuso de código de campanha. Nunca
    -- guarda mais que o IP: o resto do rastro fica no audit_log.
    ip             VARCHAR(45) NOT NULL DEFAULT '',
    redeemed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT tenants_voucher_redemption_unico UNIQUE (voucher_id, tenant_id)
);

COMMENT ON CONSTRAINT tenants_voucher_redemption_unico ON tenants_voucher_redemption IS
    'Idempotência do resgate: uma retentativa do mesmo cadastro não consome o voucher de novo.';

CREATE INDEX tenants_voucher_redemption_voucher ON tenants_voucher_redemption (voucher_id, redeemed_at DESC);
CREATE INDEX tenants_voucher_redemption_tenant  ON tenants_voucher_redemption (tenant_id);

-- ------------------------------------------------------------
-- Plano Básico
-- ------------------------------------------------------------
-- Catálogo de produto entra por migration (o voucher `devteste`, que é dado de
-- teste, NÃO — ele é semeado por script restrito a dev).
-- `price` fica NULL: a precificação ainda não foi definida e NULL diz "não
-- definido", enquanto 0 diria "gratuito".
INSERT INTO tenants_plan (name, description, price, max_instances, max_departments, max_fluxos)
SELECT 'Básico', 'Plano inicial: 3 instâncias de WhatsApp, 5 fluxos de atendimento.', NULL, 3, 3, 5
WHERE NOT EXISTS (SELECT 1 FROM tenants_plan WHERE name = 'Básico');
