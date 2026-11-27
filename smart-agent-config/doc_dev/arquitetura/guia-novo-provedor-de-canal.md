# Guia — Como adicionar um provedor de canal (WhatsApp ou outro)

Contexto e decisões: `adr-intermediario-webhooks-provedores.md`, seção 6-A.
Exemplos reais: `server/crates/infrastructure_evolution` (QR) e
`server/crates/infrastructure_meta_cloud` (credenciais).

Um provedor novo tem quatro partes: **adaptador** (controle e envio),
**normalizador** (entrada do webhook), **registro** (onde ele é ligado) e
**testes**. A tela do app não muda: ela é gerada a partir do descritor.

## 1. Adaptador — `server/crates/infrastructure_<provedor>`

Implemente, de `infrastructure_messaging`:

| Trait | Obrigatório | O que faz |
|---|---|---|
| `InstanceManager` (`ChannelLifecycle`) | sim | ciclo de vida da conexão: `get_connection_state` é a saúde. O que o provedor não tem responde `MessagingProviderError::Unsupported("motivo claro")`, nunca `Ok` de mentira. |
| `MessageSender` | sim | `send_text` e `send_media`. |
| `MessagingProvider::descritor()` | sim | o `ChannelDescriptor` (ver abaixo). |
| `QrPairing` | só se pareia por QR | `get_qr_code`. Exponha em `qr_pairing()`. |
| `TokenConnect` | só se conecta por credenciais | `conectar_com_credenciais` **valida no provedor** antes de devolver o `CanalConectado`. Exponha em `token_connect()`. |
| `PresenceControl`, `ReadReceipts`, `Reactions`, `MediaDownloader`, `ProfileQuery` | opcionais | exponha no método correspondente da fachada. |

Descritor:

- `provider`: chave única. Vai para `whatsapp_instance.provider` e para o caminho do webhook.
- `kind`: `whatsapp`, `webchat`, `telegram`, `instagram` ou `messenger`.
- `connection_mode`: escolhe o fluxo da tela. O app de hoje conduz `qr_pairing` e `token`; os demais aparecem como "atualize o app".
- `endereco`: `nome` se o adaptador recebe o nome da conexão, `id_externo` se recebe o `instance_id` (o id no provedor, gravado na conexão).
- `config_schema`: os campos do formulário (`texto`, `segredo`, `telefone`, `url`). Segredo não é ecoado na tela.
- `capacidades`: declare só as do núcleo (`health`, `reconexao`, `desconectar`, `registra_webhook`, `envio_texto`, `envio_midia`, `templates`). As opcionais e `qr_pairing`/`token_connect` são **derivadas** dos traits por `descritor_efetivo`.
- `estagio`: `experimental` até cobrir envio e recebimento; `estavel` depois.
- `eventos_webhook`: eventos que o servidor assina ao registrar o webhook. Vazio se o webhook é configurado no painel do provedor.

Tokens e segredos da conexão vão em `whatsapp_instance.api_key` (cifrado). Configuração não secreta vai em `provider_config`. Segredo do app do provedor (um por ambiente) vai no env do ambiente, pelo secret `ENV_FILE_B64`. Esse secret é alterado pelo dono, nunca à mão no servidor.

## 2. Registro — `server/apps/data_whatsapp/src/main.rs`

1. Acrescente o crate no `Cargo.toml` do `data_whatsapp` e no `members` do workspace.
2. Registre o adaptador no `ProviderRegistry` do `main`.
3. Para o tenant poder conectar, inclua a chave em `SMARTCORE_CANAIS_HABILITADOS` no `<env>.vars`. Sem isso o provedor aparece no catálogo como desabilitado.

Os handlers já roteiam por `whatsapp_instance.provider` e consultam o descritor: QR só para quem tem `QrPairing`, religar e desconectar só com a capacidade. Não escreva `if provider == ...` nos handlers.

## 3. Entrada — `server/apps/webhook_ingress`

- **Webhook por conexão, autenticado por token** (como a Evolution): implemente `WebhookNormalizer` e registre no mapa `normalizers`. A rota `/webhook/{provider}/{tenant}/{instancia}` já confere o token e que o provedor do caminho é o da conexão.
- **Webhook por app, autenticado por assinatura** (como a Meta): `aceita_rota_por_token() = false` e uma rota própria (modelo: `src/meta.rs`). Ela confere a assinatura antes de tudo, separa os eventos, resolve a conexão pelo id externo (`ResolverCanalPorIdExterno`) e chama `processar_evento`.
- Traduza para o **formato canônico do barramento** (`data.key.remoteJid`, `data.key.id` = id nativo, `pushName`, `message.conversation`/`imageMessage`…) antes do pipeline comum. Idempotência, números ignorados e rate limit vêm de graça.
- Responda 2xx rápido. Responda 5xx só em falha transitória, para o provedor reentregar.

Se o provedor chama o servidor de fora, o `provider_edge` já repassa POST e GET por `/{ambiente}/...`. Ele não muda.

## 4. Testes (rodam só na CI)

- **Adaptador**: contrato com `wiremock`. Descritor (o que existe e o que não existe), validação de credenciais (aceita e recusa), envio, saúde, e `Unsupported` no que não existe. Modelo: `infrastructure_meta_cloud/src/lib.rs`.
- **Roteamento** (`data_whatsapp`): o envio sai pelo provedor da conexão e o fluxo de QR recusa quem não tem QR. Modelo: `envio_segue_o_provedor_da_conexao`.
- **Entrada**: tradução para o formato canônico passando pelo `NormalizedMessage::parse` do worker, e assinatura. Modelo: `webhook_ingress/src/meta.rs`.
- **App**: nada a fazer se o `connection_mode` já é conhecido. Se for novo, ensine o fluxo em `integracoes_page.dart` (`_conectar`) e em `ModoConexao.suportadoNoApp`.

## 5. Checklist

- [ ] Crate do adaptador, com descritor e `Unsupported` honesto
- [ ] Registrado no `data_whatsapp` e habilitado no `<env>.vars` da dev
- [ ] Normalizador ou rota de entrada no `webhook_ingress`
- [ ] Segredos do app listados para o dono (o secret de ambiente é alterado só por ele)
- [ ] Testes de contrato e de roteamento verdes na CI
- [ ] ADR (seção 6-A, tabela "Estado") atualizado
