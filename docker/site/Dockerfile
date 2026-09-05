# =============================================================================
# Site público (smartcoreassistant.com.br) — Smart Core Assistant
# =============================================================================
# A landing page era servida pelo Django da v1, junto com o painel inteiro:
# manter o site no ar obrigava a manter app, Celery, Redis e Postgres da v1
# ligados. Aqui ela é só HTML estático, num container que não depende de nada.
#
# O conteúdo em `publico/` foi capturado da página renderizada (não do template
# Django), então é o que estava no ar, sem a máquina de templates atrás.
#
# Entrar e Criar conta estão desligados de propósito — ver o `<style>` no
# `index.html` (`[data-acesso-desativado]`). A v2 ainda não abriu ao público, e
# um botão que leva a lugar nenhum é pior que um botão apagado.
#
# Build context = docker/site/
# =============================================================================
FROM caddy:2-alpine

COPY publico/ /srv

# Sem fallback SPA: é um site de uma página só. Caminho inexistente deve dar
# 404 de verdade, não devolver a home com URL errada na barra.
RUN printf ':80 {\n\troot * /srv\n\tencode gzip zstd\n\tfile_server\n}\n' \
    > /etc/caddy/Caddyfile
