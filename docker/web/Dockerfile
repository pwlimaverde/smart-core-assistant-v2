# =============================================================================
# Imagem do client admin (Flutter Web) — Smart Core Assistant v2
# =============================================================================
# Serve o bundle estatico (HTML/JS/WASM) com fallback SPA. O CI builda o Flutter
# (por ambiente: --base-href /v2/admin/ + --dart-define) e disponibiliza ./web no
# contexto; aqui embutimos na imagem. O edge faz reverse_proxy p/ este container.
#
# Build context = raiz do repo (precisa de ./web). O Caddyfile interno e inline
# (docker/ esta no .dockerignore do build do servidor; aqui geramos via RUN).
# =============================================================================
FROM caddy:2-alpine

COPY web/ /srv

# Config interna: serve /srv na :80 com fallback SPA (try_files -> index.html).
RUN printf ':80 {\n\troot * /srv\n\tencode gzip zstd\n\ttry_files {path} /index.html\n\tfile_server\n}\n' \
    > /etc/caddy/Caddyfile
