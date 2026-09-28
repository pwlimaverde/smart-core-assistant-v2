-- Plano ia-engine-jev (J0.1) — a chave do Jev na configuração geral.
--
-- `TYPESAFE_API_KEY` é da PLATAFORMA: uma conta TypeSafe para todos os
-- tenants (decisão de 2026-09-28). Fica junto das outras chaves globais
-- (OPENAI_API_KEY, GROQ_API_KEY, GOOGLE_API_KEY) e é cadastrada na tela de
-- configurações globais do painel do superusuário, marcada como cifrada. Ao
-- contrário das chaves de LLM, não há chave por tenant: a cascata não a lê do
-- `tenants_tenantconfig.api_keys`.
--
-- `JEV_MODELO`: versão fixa (o alias `jev-latest` muda sozinho e descalibra os
-- limiares). `MOTOR_ANALISE`: llm | sombra | jev — padrão global; o tenant
-- pode sobrepor (coluna em `tenants_tenantconfig`, migração 0047).
INSERT INTO settings_manager_coresettings (key, value, encrypted, description) VALUES
    ('TYPESAFE_API_KEY', '', TRUE,
     'Chave da plataforma na TypeSafe (Jev). Uma conta para todos os tenants; sem chave por tenant. Cadastre marcada como cifrada.'),
    ('JEV_MODELO', 'jev-1.13.0', FALSE,
     'Versão fixa do Jev. Trocar a versão exige repetir a avaliação (J0) e recalibrar os limiares.'),
    ('MOTOR_ANALISE', 'llm', FALSE,
     'Motor das decisões da IA: llm (atual), sombra (os dois; vale o atual) ou jev. Sobreposto por tenants_tenantconfig.motor_analise.')
ON CONFLICT (key) DO NOTHING;
