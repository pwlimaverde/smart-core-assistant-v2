# Evolution Go com a versão do WhatsApp Web atual.
#
# Motivo: a imagem oficial busca a versão do WhatsApp Web (sw.js), mas grava só
# em `DeviceProps`. O handshake usa a versão embutida no whatsmeow
# (`store.GetWAVersion()`), que o WhatsApp recusa com 405 ClientOutdated assim
# que ela envelhece — o QR nunca é gerado e a sessão pareada não reconecta. A
# API documentada do whatsmeow para trocar essa versão é `store.SetWAVersion`
# (ver store/clientpayload.go). O patch só chama essa API com a versão que o
# próprio Evolution já buscou.
#
# Por que 0.7.3 (e não mais 0.7.2): o whatsmeow da 0.7.2 (b572e5bcb92b, 06/2026)
# não tem handler para a stanza `<status>`, que o WhatsApp passou a usar para
# os status (stories) dos contatos. O nó cai em "Didn't handle WhatsApp node"
# e nunca recebe ack; a fila offline do servidor trava atrás dele, nenhuma
# mensagem nova é entregue e, ~50 min depois, o servidor derruba o socket com
# `<stream:error><ack class="status" .../>`. Sintoma: envio funciona, a
# instância fica "connected", mas não chega mensagem recebida. O whatsmeow da
# 0.7.3 (54038813c47f) já roteia `<status>` e envia o ack. A 0.7.3 também
# corrige o vazamento de conexão do auth store (um pool novo a cada connect).
#
# O patch casa com o trecho da tag (`patch` falha se não casar) e o build usa o
# go.mod da tag, então o compilador confere a chamada.

ARG EVOLUTION_REF=0.7.3
# Revisão dos nossos patches sobre a tag (sufixo -waN da imagem e da versão).
ARG PATCH_REV=wa2

# A 0.7.3 exige Go 1.26 (go.mod); mesma imagem de build da oficial.
FROM golang:1.26.10-alpine AS build

RUN apk update && apk add --no-cache git build-base libjpeg-turbo-dev libwebp-dev patch

ARG EVOLUTION_REF
ARG PATCH_REV

WORKDIR /build

RUN git clone --depth 1 --branch "${EVOLUTION_REF}" https://github.com/EvolutionAPI/evolution-go.git .

COPY wa-version.patch /tmp/wa-version.patch
RUN patch -p1 --forward < /tmp/wa-version.patch \
 && grep -q "store.SetWAVersion" pkg/whatsmeow/service/whatsmeow.go

# Evento Archive (conversa arquivada no celular, vem na sincronização de app
# state): a 0.7.3 faz `postMap["data"].(map[string]interface{})` com o dado
# ainda como *events.Archive e entra em panic a cada evento (o whatsmeow
# recupera, mas suja o log com ERROR e stack). O patch monta o mapa do zero.
COPY archive-event.patch /tmp/archive-event.patch
RUN patch -p1 --forward < /tmp/archive-event.patch \
 && grep -q "a cada arquivamento sincronizado" pkg/whatsmeow/service/whatsmeow.go

# O compose liga CONNECT_ON_STARTUP para religar as instâncias no boot. Se uma
# versão nova trocar o nome da variável, o build falha aqui em vez de a
# Evolution subir com o WhatsApp parado sem aviso.
RUN grep -rq 'CONNECT_ON_STARTUP' pkg/config  || { echo "CONNECT_ON_STARTUP sumiu do pkg/config da evolution-go" >&2; exit 1; }

# Trava de regressão: o whatsmeow resolvido pelo go.mod precisa tratar a stanza
# `<status>`. Sem isso a recepção de mensagens trava (ver cabeçalho). Procura em
# todos os .go do módulo: o mapa nodeHandlers pode mudar de arquivo.
RUN go mod download go.mau.fi/whatsmeow \
 && WM_DIR="$(go list -m -f '{{.Dir}}' go.mau.fi/whatsmeow)" \
 && grep -qE '"status":[[:space:]]+cli\.handle' "$WM_DIR"/*.go \
 || { echo "whatsmeow sem handler da stanza <status>: a recepção trava" >&2; exit 1; }

RUN CGO_ENABLED=1 go build -ldflags "-X main.version=${EVOLUTION_REF}-${PATCH_REV}" -o server ./cmd/evolution-go

FROM alpine:3.19.1 AS final

# poppler-utils: pdftoppm, usado nas miniaturas de documento (igual à imagem oficial)
RUN apk update && apk add --no-cache tzdata ffmpeg libjpeg-turbo libwebp poppler-utils

WORKDIR /app

COPY --from=build /build/server .
COPY --from=build /build/manager/dist ./manager/dist
COPY --from=build /build/VERSION ./VERSION

# O build roda num Alpine mais novo que o final (igual à imagem oficial). Falha
# aqui se o binário CGO pedir símbolo ou biblioteca que o runtime não tem, em vez
# de o container entrar em loop de restart no deploy-infra.
RUN if ldd /app/server 2>&1 | grep -qE "Error relocating|not found"; then \
      ldd /app/server >&2; echo "binário incompatível com o runtime" >&2; exit 1; \
    fi

ENV TZ=America/Sao_Paulo

ENTRYPOINT ["/app/server"]
