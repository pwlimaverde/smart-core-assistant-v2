FROM caddy:2-alpine
COPY docker/edge/Caddyfile /etc/caddy/Caddyfile
# O build do Flutter Web e colocado em ./web pelo CI e copiado para ca
COPY web/ /srv/admin
