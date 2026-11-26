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

# A 0.7.3 exige Go 1.26 (go.mod); mesma imagem de build da oficial.
FROM golang:1.26.10-alpine AS build

RUN apk update && apk add --no-cache git build-base libjpeg-turbo-dev libwebp-dev patch

ARG EVOLUTION_REF

WORKDIR /build

RUN git clone --depth 1 --branch "${EVOLUTION_REF}" https://github.com/EvolutionAPI/evolution-go.git .

COPY wa-version.patch /tmp/wa-version.patch
RUN patch -p1 --forward < /tmp/wa-version.patch \
 && grep -q "store.SetWAVersion" pkg/whatsmeow/service/whatsmeow.go

# Trava de regressão: o whatsmeow resolvido pelo go.mod precisa tratar a stanza
# `<status>`. Sem isso a recepção de mensagens trava (ver cabeçalho).
RUN go mod download go.mau.fi/whatsmeow \
 && WM_DIR="$(go list -m -f '{{.Dir}}' go.mau.fi/whatsmeow)" \
 && grep -qE '"status":[[:space:]]+cli\.handle' "$WM_DIR/client.go" \
 || { echo "whatsmeow sem handler da stanza <status>: a recepção trava" >&2; exit 1; }

RUN CGO_ENABLED=1 go build -ldflags "-X main.version=${EVOLUTION_REF}-wa1" -o server ./cmd/evolution-go

FROM alpine:3.19.1 AS final

# poppler-utils: pdftoppm, usado nas miniaturas de documento (igual à imagem oficial)
RUN apk update && apk add --no-cache tzdata ffmpeg libjpeg-turbo libwebp poppler-utils

WORKDIR /app

COPY --from=build /build/server .
COPY --from=build /build/manager/dist ./manager/dist
COPY --from=build /build/VERSION ./VERSION

ENV TZ=America/Sao_Paulo

ENTRYPOINT ["/app/server"]
