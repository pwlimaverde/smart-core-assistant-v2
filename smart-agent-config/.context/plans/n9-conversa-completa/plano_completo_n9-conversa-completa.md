# N9 — A conversa completa

> **Origem:** `26-levantamento-paridade-v1-v2.md` §3.5 e `27-mapa-telas-rotas-v2.md`
> §A.3/§D.1. **Caminho crítico** do port: é o que o atendente sente em toda
> conversa e o que hoje o legado faz melhor.
> **Escala:** LARGE · **Depende de:** N8.5 (o buffer muda o fluxo por onde a
> mídia passa). **Quatro entregas:** N9a mídia · N9b leitura/presença/citação ·
> N9c busca e operação do quadro · N9d ficha completa.
> **Documentação de apoio:** `info_aux_n9-conversa-completa.md` — **leia o aviso
> sobre o contrato da evolution-go antes de escrever qualquer chamada HTTP.**

---

## O que já existe (não refazer)

Colunas vindas do fluxo, arrastar com as regras de transição conferidas contra a
v1, assumir com saudação na mesma transação, chat em streaming
(`StreamAtendimentos`) com reconexão, enviar texto, ficha com etiquetas e notas,
selo "gerado por IA" e resumo de mídia.

E, no servidor, **quatro capacidades prontas sem nenhum chamador**:
`SendWhatsappMedia`, `MarkWhatsappMessageRead`, `SetWhatsappPresence`,
`SendWhatsappReaction` — mais `GetWhatsappProfilePicture` e
`TransferirAtendimentoParaFluxo`. Boa parte desta fase é **ligar**, não construir.

---

# N9a — Mídia na conversa

## E1 — Enviar mídia (anexo)

### Contrato

Upload em duas etapas, para não trafegar binário no gRPC-Web:

1. `SolicitarUploadMidia(atendimento_id, nome_arquivo, mimetype, bytes)` →
   devolve **URL pré-assinada PUT** (`data_storage`, prefixo
   `media/{tenant}/outbound/...`) + a chave do objeto.
2. Cliente faz `PUT` direto no R2 com o `Content-Type` **idêntico** ao assinado
   (o R2 recusa divergência — ver `info_aux`).
3. `EnviarMidiaAtendimento(atendimento_id, chave, tipo, legenda, action_id?)` →
   persiste a mensagem (`arquivo_midia` = chave), contabiliza quota
   (`RegisterStorageUsage`) e publica no outbox; o worker envia via
   🔌 `SendWhatsappMedia`.

**Validação no servidor** (nunca só no cliente): mimetype permitido conferido
por **magic bytes**, tamanho máximo por tipo, e quota de storage do tenant — que
sai do modo log-only para este caminho (o guard já existe desde a N7.1).

**Base64 sem prefixo** ao entregar à evolution-go (erro clássico, ver `info_aux`).

### Cliente

`file_picker` 11.0.2 — **atenção:** na Web vem `bytes`, no Windows vem `path`. O
gateway abstrai isso; a tela nunca vê a diferença. Pré-visualização antes de
enviar, barra de progresso, e cancelar.

### Observabilidade & Auditoria

- **Logs:** span `atendimento.midia_enviada` com `tenant_id`, `atendimento_id`,
  `tipo`, `bytes`, `duracao_ms`. `skip_all`: nome de arquivo pode conter PII.
- **Auditoria:** `mensagem.midia_enviada` — quem enviou, para qual atendimento,
  tipo e tamanho. **Sem** o nome do arquivo na descrição e **sem** a URL.
- **Sanitização:** a URL pré-assinada é **credencial temporária** —
  `secrecy::SecretString`, nunca em log, span, métrica ou erro devolvido ao
  cliente.

### Testes

Mimetype mentido (extensão `.jpg`, conteúdo `.exe`) → recusado. Arquivo acima do
limite → recusado antes do upload. Quota estourada → recusado com erro claro.
Sucesso → mensagem na thread com `status_envio` evoluindo.

## E2 — Ver e baixar a mídia recebida

### Contrato

`MensagemThread` ganha `midia` opcional: `{ kind, url_assinada, mimetype,
filename, size_bytes, seconds?, is_ptt? }`. A URL é gerada **no momento da
leitura da thread**, com TTL curto (5–15 min).

`ListarMidiasAtendimento(atendimento_id)` para a galeria da ficha (N9d).

**Decisão:** não devolver URL permanente nem proxy pelo backend. Presign curto é
o que o R2 faz bem e evita o servidor virar CDN.

### Cliente

- **Imagem**: thumb na bolha → `photo_view` em lightbox com zoom. ✅ Web + Windows.
- **Áudio**: `just_audio` com duração e marca de PTT. ✅ Web + Windows (CORS
  configurado — ver `info_aux`).
- **Documento**: extensão, nome, tamanho; baixar via `url_launcher`; PDF abre no
  visualizador do sistema.
- **Vídeo**: 🚨 **`video_player` não suporta Windows.** Fazer **spike de
  `media_kit`** antes de escrever a tela. Fallback aceitável se o spike falhar:
  abrir no player do sistema via `url_launcher`. **Não travar a fase por vídeo.**

### Observabilidade & Auditoria

- **Logs:** `midia.presign_emitida` (chave, ttl_segundos). Nunca a URL.
- **Auditoria:** `midia.acessada` — é **acesso a dado protegido** (§08 4.2):
  quem, qual mensagem, quando. Sem a URL na descrição.
- **Sanitização:** URL assinada em `SecretString`; erro de presign nunca vaza a
  chave do objeto para o cliente.

## E3 — Gravar áudio

`record` 5.1.2, com timer, cancelar e enviar — reusando o caminho de upload da
E1. **Codec difere por plataforma** (PCM16/WAV na Web, AAC-LC no Windows); o
spike da E2 decide entre padronizar em WAV e converter no servidor ou aceitar o
nativo. Permissão de microfone tratada com estado próprio (negada ≠ indisponível).

**Auditoria:** mesma da E1 (é mídia enviada, com `tipo=audio`, `is_ptt=true`).

---

# N9b — Leitura, presença e citação

## E4 — Marcar como lida e contador de não lidas

`MarcarAtendimentoLido(atendimento_id)`: marca as mensagens do contato como
lidas (`marcar_como_lida` já existe no repositório) e espelha no WhatsApp via
🔌 `MarkWhatsappMessageRead` (`POST /message/markread` — path real, ver aviso).

Gatilho: abrir a conversa **e** rolar até o fim (abrir sem ler não marca).

Contadores: por atendimento (campo em `AtendimentoResumo`) e global
(`GetNaoLidas`), alimentando o badge do cartão e o sino da topbar.

**Auditoria:** **sem evento** — intencional. Marcar lida é estado operacional
trivial e altíssimo volume; auditar inundaria a trilha. O `data_lida` na
mensagem já é o registro.

## E5 — Presença "digitando"

`DefinirPresencaAtendimento(atendimento_id, estado)` → 🔌 `SetWhatsappPresence`
(`POST /message/presence`, estados `composing`/`recording`/`paused`).

**Cuidado com volume:** reenviar a cada ~4 s enquanto digita (padrão da
plataforma), com **debounce no cliente** e `paused` ao parar. O limite prático
da evolution-go é ~50 req/s por instância — presença é o endpoint mais falador
do sistema. Nunca disparar por tecla.

Presença **do contato** (mostrar "digitando" no cabeçalho) chega pelo evento
`PRESENCE`, cujo consumo é entregue na **N8.5.5**.

**Auditoria:** **sem evento** — efêmero e de alto volume. Log em DEBUG.

## E6 — Citação (responder mensagem)

Aditivo no proto: `mensagem_citada_id` em `SendOutboundMessageRequest`; `quoted`
(remetente + preview) em `MensagemThread`. As colunas
(`mensagem_citada_id`, `quoted_preview`) **existem desde a migration 0006**.

Cliente: duplo clique/ação na bolha abre o banner de resposta no composer.

## E7 — Ticks de entrega e leitura

`data_entregue`/`data_lida` na `MensagemThread` (colunas existentes) →
pendente/enviado/entregue/lido/falhou na bolha. O evento `MESSAGE_UPDATE` já é
consumido pelo worker; falta só expor os campos.

## E8 — Refinamentos de leitura da conversa

Separador por dia, agrupamento de bolhas consecutivas do mesmo remetente, botão
flutuante "ir para o fim". **Só cliente**, sem contrato — mas é o que faz a
conversa parecer conversa.

---

# N9c — Operar o quadro com volume

## E9 — Busca e filtros

Extensão aditiva de `ListAtendimentosRequest`: `q`, `prioridade`, `etiqueta_id`,
`atendente_id`, `apenas_nao_lidos`, `offset`.

`q` busca **no servidor** (ILIKE em nome do contato, nome de perfil, telefone e
assunto — mesmos campos da v1), com teto de linhas. Filtrar no cliente
esconderia quem ficou além do teto — mesma decisão já tomada em contatos.

Cliente: campo de busca com debounce 300 ms e popover de filtros com contador de
ativos (como a v1).

**Sanitização:** **não logar o termo buscado** — pode ser telefone ou nome.
Logar apenas o número de resultados.

## E10 — Prioridade, atribuir, exportar

- `DefinirPrioridadeAtendimento` — coluna existe, sempre `normal` hoje. Chip
  colorido no cartão, alteração pela ficha.
- `AtribuirAtendimento(atendimento_id, atendente_id)` — atribuir a outra pessoa
  (hoje só assume quem arrasta). Regras: só atendente ativo; registrar movimento.
- `ExportAtendimentosCsv` (server streaming, como o `ExportTenantsCsv` que já
  existe) — do fluxo e filtros correntes.
- `TransferirMeuAtendimentoParaFluxo` — expor na borda o RPC 🔌 que hoje só a IA
  usa; popover com fluxos disponíveis, como na v1.

**Auditoria:** `atendimento.prioridade_alterada`, `atendimento.atribuido`,
`atendimento.transferido` e **`atendimento.exportado`** — este último é
**exportação em massa de dado de cliente**: auditar quem, quando, filtros e
quantidade de linhas. É o evento mais sensível da fase.

## E11 — Preview e foto no cartão

Preview da última mensagem (com `↳` quando é do atendente) e foto do contato no
cartão e no chat. A foto vem de `whatsapp_contact` (populada pelo evento
`CONTACTS` na N8.5.5) ou sob demanda por 🔌 `GetWhatsappProfilePicture`
(`POST /user/avatar` — path real).

## E12 — Modos de foco e atalhos

Quadro / dividido / conversa, com `Alt+1/2/3`, `Esc` e `i`. Só cliente. Persistir
a preferência localmente.

---

# N9d — A ficha completa

## E13 — Campos personalizados

Catálogo por fluxo (`/tenant/fluxos/:id/campos`): `ListMyCamposPersonalizados`,
`CreateMyCampoPersonalizado`, `UpdateMyCampoPersonalizado`,
`DesativarMyCampoPersonalizado`. As tabelas (`atu_campo_personalizado`,
`atu_valor_campo`) e o repositório (`campos.rs`) **já existem**; o `Responder` já
consome os campos como contexto.

Na ficha: valor, **origem** (BOT/MANUAL/IMPORT), **barra de confiança** quando a
origem é BOT, e edição inline → `SetValorCampoAtendimento`.

**Auditoria:** `campo_personalizado.alterado` — registrar **qual campo**, nunca
o valor (pode ser CPF, endereço, o que o tenant quiser).

## E14 — Galeria e linha do tempo

- `ListarMidiasAtendimento` → grade dos últimos itens, com thumb.
- `ListarMovimentosAtendimento` → eventos de `oraculo_movimento_fluxo` (que são
  gravados desde sempre e nunca foram lidos): label, descrição, **autor**,
  timestamp, e a distinção manual × automático.

## E15 — Etiquetas e notas completas

`/tenant/etiquetas` (catálogo com `UpdateEtiqueta`/`DesativarEtiqueta`) e
`RemoverNota` na ficha. Etiqueta desativada continua aparecendo onde já estava —
regra já estabelecida no ciclo anterior.

---

## Sequência

```
N9a  E1 → E2 (spike de vídeo AQUI) → E3
N9b  E4 → E5 → E6 → E7 → E8
N9c  E9 → E10 → E11 → E12
N9d  E13 → E14 → E15
```

Cada bloco é entregável sozinho e deixa o sistema mais usável que antes. O spike
de vídeo (`media_kit`) acontece **no começo da E2** — é a única incógnita técnica
real da fase.

## Riscos

| Risco | Mitigação |
|---|---|
| 🚨 **Vídeo não roda no Windows** (`video_player`) | spike de `media_kit` antes da tela; fallback: abrir no player do sistema. Imagem e áudio não dependem disso |
| Codec de áudio divergente Web × Windows | decidir no spike: padronizar WAV e converter, ou aceitar o nativo. Validar com envio real |
| CORS do R2 quebrar mídia na Web | configurar via API (não há dashboard), incluir `Range`, testar seek de áudio antes de fechar a E2 |
| Presign com `Content-Type` divergente | assinar e enviar o mesmo valor; teste automatizado do par assinatura/PUT |
| Presença estourar rate limit | debounce no cliente, `paused` ao parar, nunca disparar por tecla |
| Quota de storage passar a morder de verdade | ligar o guard só neste caminho e observar antes do enforce global (N12.3) |
| Busca lenta com volume | índices para o ILIKE (`pg_trgm`) avaliados junto com a query |

## Definition of Done

- [ ] Atendente recebe áudio, ouve, responde com imagem, e o cliente recebe.
- [ ] Conversa some do contador ao ser lida; o contato vê "digitando".
- [ ] Responder citando funciona; ticks refletem entrega e leitura.
- [ ] Buscar por telefone acha a conversa; filtros combinam.
- [ ] Prioridade, atribuição e transferência manual operáveis pela tela.
- [ ] Ficha mostra campos personalizados (com origem e confiança), galeria e
      linha do tempo.
- [ ] Nenhuma URL assinada, valor de campo ou termo de busca em log/auditoria.
- [ ] Exportação de CSV auditada com autor, filtros e contagem.
- [ ] `.\infra\test-local.ps1` e `.\infra\test-flutter.ps1` verdes; ratchet de
      cobertura mantido.
