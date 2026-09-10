-- D3 — desligar o bot por instância (plano `regras-do-bot-e-permissoes`).
--
-- A v1 tinha `AppInstance.resposta_bot` e a rota `instances/<pk>/toggle-bot/`: o
-- dono calava a IA de um número inteiro para atender manualmente — plantão,
-- campanha, um cliente que pediu para falar com gente. A v2 perdeu isso na
-- migração e ficou só com o desligamento por conversa
-- (`oraculo_atendimento.bot_pode_atender`), que além de tudo não tem controle
-- em tela nenhuma.
--
-- `DEFAULT TRUE` e `NOT NULL`: toda instância existente continua respondendo
-- exatamente como hoje. A migração não muda comportamento de ninguém.
ALTER TABLE whatsapp_instance
    ADD COLUMN IF NOT EXISTS resposta_bot BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN whatsapp_instance.resposta_bot IS
    'Quando false, a IA nao responde automaticamente NENHUMA conversa desta '
    'instancia. E a barreira mais externa: precede o bot_pode_atender do '
    'atendimento e o bloqueio por atendente humano ativo.';
