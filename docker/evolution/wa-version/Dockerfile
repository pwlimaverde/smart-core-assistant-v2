# Evolution Go com a versão do WhatsApp Web atual.
#
# Motivo: a imagem oficial 0.7.2 busca a versão do WhatsApp Web (sw.js), mas
# grava só em `DeviceProps`. O handshake usa a versão embutida no whatsmeow
# (`store.GetWAVersion()`), que o WhatsApp recusa com 405 ClientOutdated — o
# QR nunca é gerado. A API documentada do whatsmeow para trocar essa versão é
# `store.SetWAVersion` (ver store/clientpayload.go). O patch só chama essa API
# com a versão que o próprio Evolution já buscou.
#
# O patch casa com o trecho exato da tag 0.7.2 (`patch` falha se não casar)
# e o build usa o mesmo go.mod da tag, então o compilador confere a chamada.

ARG EVOLUTION_REF=0.7.2

FROM golang:1.25.0-alpine AS build

RUN apk update && apk add --no-cache git build-base libjpeg-turbo-dev libwebp-dev patch

ARG EVOLUTION_REF

WORKDIR /build

RUN git clone --depth 1 --branch "${EVOLUTION_REF}" https://github.com/EvolutionAPI/evolution-go.git .

COPY wa-version.patch /tmp/wa-version.patch
RUN patch -p1 --forward < /tmp/wa-version.patch \
 && grep -q "store.SetWAVersion" pkg/whatsmeow/service/whatsmeow.go

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
