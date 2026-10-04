-- C2: Limpeza de URLs do WhatsApp em campo conteudo (migração de dados)
--
-- Problema: imagens, áudios e vídeos SEM legenda tinha URL da CDN do WhatsApp
-- copiada para `conteudo`. Isso alimentava a IA com lixo e poluía o histórico.
--
-- Solução: limpar todas as mensagens onde conteudo é uma URL HTTPS do WhatsApp
-- (que começa com https:// e é o único campo preenchido para esses tipos).
--
-- Escopo: oraculo_mensagem.conteudo onde tipo in ('audio', 'image', 'video')
-- e conteudo é uma URL (começa com 'https://').
--
-- Nota: A análise posterior (worker, na coluna analise_midia) vai popular os
-- campos de transcrição/descrição. Esta limpeza só remove o lixo da CDN.

UPDATE oraculo_mensagem
SET conteudo = ''
WHERE tipo IN ('audio', 'image', 'video')
  AND conteudo LIKE 'https://%'
  AND conteudo != '';

-- Auditoria: log da quantidade modificada (opcional, para validação)
-- SELECT COUNT(*) FROM oraculo_mensagem
-- WHERE tipo IN ('audio', 'image', 'video')
--   AND conteudo LIKE 'https://%';
