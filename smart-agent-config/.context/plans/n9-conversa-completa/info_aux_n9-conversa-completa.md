# Documentação Auxiliar — N9 Conversa Completa

> Gerado em: 2026-08-09
> Plano canônico: `.context/plans/n9-conversa-completa.md`
> Plano completo: `.context/plans/n9-conversa-completa/plano_completo_n9-conversa-completa.md`
> Referências brutas nesta pasta: `ref_evolution_go.md`, `ref_cloudflare_r2.md`

---

## ⚠️ AVISO CRÍTICO — o contrato da evolution-go não é o da Evolution API

A pesquisa web devolveu os endpoints da **Evolution API v2 (Node, "foundation")**.
**O projeto NÃO usa essa API.** Usa a **evolution-go 0.7.1**, cujo contrato é
diferente. Confirmado lendo o cliente real do projeto
(`server/crates/infrastructure_evolution/src/provider.rs`):

| Ação | Pesquisa web (Evolution v2) — **NÃO USAR** | **Código real do projeto** (fonte da verdade) |
|---|---|---|
| Enviar texto | `POST /message/sendText/{instance}` | `POST /send/text` (linha 433) |
| **Enviar mídia** | `POST /message/sendMedia/{instance}` | **`POST /send/media`** (linha 525) |
| **Marcar lida** | `PUT /chat/markMessageAsRead/{instance}` | **`POST /message/markread`** (linha 636) |
| **Presença** | `POST /chat/sendPresence/{instance}` | **`POST /message/presence`** (linha 607) |
| Reação | — | `POST /message/react` (linha 669) |
| **Baixar mídia** | — | **`POST /message/downloadmedia`** (linha 706) |
| **Foto de perfil** | não confirmado | **`POST /user/avatar`** (linha 742) |
| QR | `GET /instance/connect/{instance}` | `GET /instance/qr` (linha 319) |
| Logout | `POST /instance/logout/{instance}` | `DELETE /instance/logout` (linha 283) |
| Estado | `GET /instance/connectionState/{i}` | `GET /instance/status` (linha 343) |

**Regra para a implementação desta fase:** a fonte da verdade do contrato é
`infrastructure_evolution/src/provider.rs` + os testes em
`crates/infrastructure_evolution/tests/client_tests.rs`. O `ref_evolution_go.md`
serve apenas como **contexto conceitual** (semântica de presença, formato de
`remoteJid`, comportamento de retry do webhook) — nunca como fonte de path.

Ver também a memória do projeto: *"Contrato da evolution-go — envelope `{data}`,
delete por UUID, QR é imagem"*.

### O que aproveitamos do relatório (conceitual, aplicável)

- **Base64 sem prefixo**: o campo de mídia recebe base64 puro, sem
  `data:image/jpeg;base64,`. Erro comum e silencioso.
- **`remoteJid`**: `5511999999999@s.whatsapp.net` para contato,
  `<id>@g.us` para grupo (este último a N8.5.1 descarta).
- **Presença**: estados `composing` / `recording` / `paused`, com `delay` em ms.
  Padrão de uso: reenviar a cada ~4 s enquanto digita; encerrar com `paused`.
- **Rate limit**: ~50 req/s por instância (recomendação). Relevante para o
  disparo de presença, que é o mais falador.
- **Webhook**: espera 2xx em até 30 s, com até 5 retentativas.

### Já implementado e sem chamador (🔌)

`send_media`, `set_presence`, `send_reaction`, `get_profile_picture` e o RPC
`MarkWhatsappMessageRead` existem no `data_whatsapp` e **nenhum caller os usa**.
Esta fase é, em boa parte, ligar o que já está pronto e testado.

---

## Cloudflare R2 (via `aws-sdk-s3` v1)

Doc local: `doc_dev/libs/rust/aws_sdk_s3.md` (✅ ATUALIZADA, jun/2026).
Relatório completo: `ref_cloudflare_r2.md`.

### Presign GET (ler mídia no cliente)

- Expiração aceita: **1 s a 7 dias**. Usar janela curta (5–15 min) para mídia de
  conversa — a URL não deve sobreviver ao compartilhamento acidental.
- `PresigningConfig::builder().expires_in(Duration::from_secs(900))`.

### Presign PUT (upload direto do cliente) — **decisão**

O relatório recomenda presign PUT para arquivos grandes e passar pelo backend
para pequenos. **Decisão para esta fase: upload direto via presign PUT**, porque:

- evita trafegar binário pelo gRPC-Web (que teria de fragmentar);
- o `data_storage` já sabe assinar (`PresignFile` existe);
- a quota de storage continua sendo contabilizada no servidor, no momento em que
  a mídia é confirmada (`RegisterStorageUsage`).

**Pegadinhas confirmadas:**
- `Content-Type` na assinatura precisa **bater exatamente** com o do PUT. O R2 é
  mais rigoroso que o S3 nisso.
- Headers assinados vs não assinados: o R2 recusa divergência.

### CORS (obrigatório para Flutter Web)

- **Só configurável por API/Wrangler** — o dashboard do R2 não expõe CORS.
- Propagação de até 30 s.
- `AllowedOrigins` exato, **sem barra no fim**.
- Para áudio/vídeo com seek, incluir `Range` em `AllowedHeaders` e expor
  `Content-Range`/`ETag` — sem isso o player Web falha ao buscar posição.

```json
{
  "CORSRules": [{
    "AllowedOrigins": ["https://<dominio-prod>", "http://localhost:PORTA"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["Content-Type", "Range"],
    "ExposeHeaders": ["ETag", "Content-Range", "Content-Length"],
    "MaxAgeSeconds": 3600
  }]
}
```

### Diferenças R2 × S3 relevantes

- `Content-MD5` é ignorado pelo R2.
- ETag de multipart **não é MD5** — não usar como checksum.
- Lifecycle por prefixo funciona (o projeto já usa `media/{tenant}/...`);
  deleção efetiva em até 24 h após a expiração.

---

## Libs Flutter de mídia (docs criados nesta rodada)

Todas gravadas na central em `doc_dev/libs/flutter/`, verificadas em 2026-08-09.

| Lib | Versão | Web | Windows | Observação |
|---|---|---|---|---|
| `file_picker` | 11.0.2 | ✅ bytes (`files.first.bytes`) | ✅ path (`files.first.path`) | caminho diferente por plataforma — abstrair no gateway |
| `record` | 5.1.2 | ⚠️ via MediaRecorder, **codecs limitados** | ✅ Windows Media Foundation | recomendação: PCM16/WAV na Web, AAC-LC no Windows |
| `just_audio` | 0.9.34 | ✅ Web Audio API | ✅ | CORS afeta a Web (ver seção do R2) |
| **`video_player`** | 2.8.5 | ✅ | ❌ **NÃO SUPORTA WINDOWS** | 🚨 **bloqueador** |
| `photo_view` | 0.14.0 | ✅ | ✅ | agnóstico de plataforma |

### 🚨 Decisão forçada: vídeo no desktop

`video_player` não roda no Windows, e o app do tenant **é empacotado para
Windows** (N5.1). Alternativas levantadas: `media_kit` (libmpv, mais moderna e
a recomendada pela comunidade), `better_player`, `flutter_vlc_player` (exige
runtime do VLC).

**Encaminhamento:** tratar como **spike da N9.2** — avaliar `media_kit` nas duas
plataformas antes de escrever a tela. Se o spike falhar, o fallback aceitável é
**abrir o vídeo no navegador/player do sistema** via `url_launcher` (já é
dependência do projeto) com a URL pré-assinada, entregando imagem e áudio
inline e vídeo por link. Não travar a fase inteira por causa de vídeo.

### Gravação de áudio: codec por plataforma

O `record` grava em formatos diferentes por plataforma. O WhatsApp espera áudio
de voz em formato compatível (a v1 enviava o que vinha do navegador). Definir no
spike: gravar em **WAV/PCM16** e converter no servidor, **ou** aceitar o formato
nativo de cada plataforma e deixar a Evolution/WhatsApp resolver. A segunda
opção é mais barata; validar com envio real antes de fechar.

---

## Libs Rust (todas USAR LOCAL — central atualizada)

| Lib | Versão | Doc local | Uso nesta fase |
|---|---|---|---|
| `aws-sdk-s3` | 1.x | `rust/aws_sdk_s3.md` (jun/2026) | presign GET/PUT |
| `tonic` / `tonic-web` | 0.14.6 | `rust/tonic.md` (jun/2026) | RPCs novos + fachada gRPC-Web |
| `sqlx` | 0.9 | `rust/sqlx.md` (jun/2026) | queries novas (validar contra banco real) |
| `redis` | 0.25 | `rust/redis.md` (jun/2026) | cache de presença/não lidas |
| `reqwest` | 0.12.4 | `rust/reqwest.md` (mai/2026) | cliente Evolution (já existe) |

---

## Grupo C — Observabilidade e Auditoria desta fase

| Etapa | Span/log | `audit_log` | Risco de vazamento |
|---|---|---|---|
| Enviar mídia | `atendimento.midia_enviada` (tipo, bytes, duracao_ms) | **sim** — `mensagem.midia_enviada` | nome de arquivo pode ter PII; **nunca** logar o binário nem a URL assinada |
| Ver mídia (presign) | `midia.presign_emitida` (chave, ttl) | **sim** — `midia.acessada` (é acesso a dado protegido, §08 4.2) | **URL assinada é credencial temporária** — nunca logar |
| Marcar lida | `atendimento.lido` | não (intencional — estado operacional trivial, alto volume) | — |
| Presença | DEBUG apenas | não (efêmero, alto volume) | — |
| Busca/filtros | span da listagem com contagem | não | **não logar o termo buscado** (pode ser telefone/nome) |
| Atribuir/prioridade | `atendimento.atribuido` / `.prioridade_alterada` | **sim** nos dois | — |
| Exportar CSV | `atendimento.exportado` (linhas) | **sim** — exportação em massa de dado de cliente | o CSV **contém PII**: auditar quem exportou, quando e quantas linhas |
| Campos personalizados | `campo.valor_definido` | **sim** — `campo_personalizado.alterado` | o **valor** pode ser PII: auditar o campo, não o valor |
| Timeline | leitura simples | não | — |

**Política de instrumentação** (arquitetura de erros): `#[tracing::instrument(err)]`
só onde todo erro é falha real de infra; repositórios de tenant via
`run_in_tenant_transaction` + `#[instrument(skip_all)]`. Toda struct com URL
assinada ou credencial usa `secrecy::SecretString`.
