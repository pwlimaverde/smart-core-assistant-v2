# Documentação Auxiliar — Pendências pós-paridade

> Gerado em: 2026-09-19
> Plano canônico: `.context/plans/pendencias-pos-paridade.md`
> Plano completo: `.context/plans/pendencias-pos-paridade/plano_completo_pendencias-pos-paridade.md`
> Origem das pendências: varredura de 19/09 sobre os planos N9–N13, regras,
> painel CRM, doc 36 (seções "fica de fora") e doc 37 (paridade P1–P12).

## Triagem da central local (`doc_dev/libs/`)

| Lib | Stack | Versão no manifest | Doc local | Estado | Motivo |
|---|---|---|---|---|---|
| sqlx | rust | 0.9 | `rust/sqlx.md` (2026-06-10) | USAR LOCAL | O plano usa só `sqlx::query`/`query_as::<_, T>` em runtime, exercitados pela CI verde de 19/09 (run 35460056817). Verificação passou de 90 dias por pouco; nenhuma API nova envolvida. |
| tokio | rust | 1.38 | `rust/tokio.md` (2026-05-31) | USAR LOCAL | `tokio::spawn` e `time` apenas, idem acima. |
| tracing | rust | 0.1.40 | `rust/tracing.md` (2026-05-31) | USAR LOCAL | `#[instrument(skip_all, fields(...))]`, `info!/warn!` — padrão do projeto. |
| serde_json | rust | 1.x | `rust/serde.md` | USAR LOCAL | `json!`, `Map`. Atenção: chave dinâmica no `json!` — montar `Map` à mão (achado do P8). |
| flutter_bloc / get_it / mocktail | flutter | 9.1 / 9.2 / 1.0.4 | `flutter/*.md` (2026-06-14 / 05-31) | USAR LOCAL | Padrão RSOE já em uso. |
| **flutter_local_notifications** | flutter | — (nova) | `flutter/flutter_local_notifications.md` (2026-09-19) | **CRIADO** | Aviso nativo do Windows (P16-c). |
| **url_launcher** | flutter | ^6.3.1 (já no tenant_module) | `flutter/url_launcher.md` (2026-09-19) | **CRIADO** | Entrou no P11 sem doc; o P13 não usa, o P16 reaproveita o fake de teste. |

> Context7 estava sem autenticação nesta sessão; as duas libs novas foram
> coletadas do pub.dev/GitHub por subagente e gravadas na central.

## Libs Flutter

### flutter_local_notifications (22.3.1) — `doc_dev/libs/flutter/flutter_local_notifications.md`

- **Windows exige** `WindowsInitializationSettings(appName, appUserModelId, guid)`.
  O GUID é gerado **uma vez** e fica fixo no código (trocar o GUID "some" o
  histórico de notificações do app no Windows).
- App empacotado como **zip, sem MSIX**: a notificação aparece; cancelar e
  gerenciar histórico não funcionam. Serve para o nosso caso (alerta de disparo
  único).
- Clique chega em `onDidReceiveNotificationResponse(NotificationResponse r)`,
  com `r.payload` (string). Usar JSON com `atendimento_id`.
- **Web:** não importar a lib em código que o build web compila. Usar import
  condicional (`if (dart.library.js_interop)`), mesmo padrão do
  `atendimento_gateway_factory.dart`. No web, o aviso continua sendo o SnackBar
  do quadro (B5).
- **Conferir na implementação:** a assinatura de `show()` na 22.x (parâmetros
  posicionais vs nomeados mudaram entre majors). O doc local traz exemplos em
  duas formas; valer o que o `dart analyze` aceitar.

### url_launcher (6.3.2) — `doc_dev/libs/flutter/url_launcher.md`

- `launchUrl(uri, mode: LaunchMode.externalApplication)`; retorno `false` é
  falha da plataforma, não exceção.
- Teste: `UrlLauncherPlatform.instance = FakeUrlLauncher()` no `setUp`.

## Libs Rust / Python

Sem libs novas. Padrões do projeto que o plano precisa respeitar (achados do
P1–P12, registrados no doc 37):

- **Consulta nova = sem macro** (`sqlx::query_as::<_, T>`). O cache `.sqlx` é
  offline; mudar o texto de um `query!` quebra o `cargo check` da CI.
- Método novo em trait de adapter vai **dentro do `impl`**, não no fim do
  arquivo (o fim do `adapters/atendimento.rs` é o `mod tests`).
- `EventoBruto.payload` é `String` → `serde_json::from_str`.
- Nome de modelo Dart **não pode colidir** com tipo gerado do contrato: o
  `dependencies_module` reexporta o `api_client`.
- Piso de cobertura Flutter **78%** é gate: tela nova entra com teste de widget.

## Serviços Externos

### evolution-go (`evoapicloud/evolution-go`, tag em `EVOLUTION_IMAGE_TAG`)

Fonte do contrato real: Swagger em `http://<host>:8082/swagger/doc.json` (só
alcançável no VPS). Memória do projeto: `evolution-go-contrato`.

#### Autenticação
Header `apikey` com o **token da instância** (não o nome).

#### `POST /user/avatar` — foto de perfil do contato
- **Implementado em:** `server/crates/infrastructure_evolution/src/provider.rs`
  (`ProfileQuery::get_profile_picture`) e exposto no `data_whatsapp` pela rota
  `GetWhatsappProfilePicture` (payload `{ id: <instância>, number }`).
- **Body:** `{ "number": "5511999998888", "preview": false }`.
- **Resposta real:** envelope `{ "data": { ... }, "message": "success" }` —
  **toda** resposta da evolution-go vem embrulhada.
- 🚨 **Defeito latente:** o cliente desserializa direto em `AvatarResp`
  (`profilePictureUrl` | `url` no topo), sem passar pelo `json_do_provedor`, e o
  teste com wiremock usa a resposta **sem** envelope. Contra o servidor real a
  foto volta sempre `None`. Corrigir antes de qualquer tela (P13, passo 1),
  aceitando os dois formatos e confirmando o nome do campo no Swagger.
- **URL devolvida** é do CDN do WhatsApp (`pps.whatsapp.net`), assinada e **com
  validade** (dias). Guardar a URL e a data da verificação; tela trata imagem
  quebrada como "sem foto" e pede nova busca.

#### Evento `CONTACTS` (webhook)
Já consumido desde o P8 (`processar_contato_atualizado`): grava
`nome_perfil_whatsapp` e `foto_perfil_url_origem` só de contatos existentes.

## Grupo C — Observabilidade e auditoria por fase

| Fase | Logs / trace | `audit_log` | Risco de vazamento |
|---|---|---|---|
| P13 foto | span `contato.foto` com `atendimento_id`, `origem` (`cache`/`provedor`/`sem_foto`), duração | **sem evento** (enriquecimento derivado, como decidido na N11 E6) | telefone só mascarado; URL da foto nunca em log (é assinada e identifica a pessoa) |
| P14 etiquetas | contagem `etiquetas_aplicadas` e `etiquetas_bloqueadas` no span `ia.analise` | `etiqueta.aplicada_por_ia` (atendimento, etiqueta, confiança; `user_id` nulo) e `etiqueta.removida` com a marca de bloqueio | nome de etiqueta é do tenant, não PII |
| P15 contato | contagem `campos_contato_preenchidos` | `contato.enriquecido_por_ia` com a **lista de campos**, nunca valores | nome/e-mail/documento são PII direta — fora de log, span, métrica e descrição |
| P16 quadro | `quadro.revisao_pendente` (contagem) no worker; nenhum log no cliente | `atendimento.revisao_concluida` (quem marcou) | nenhum conteúdo de mensagem na notificação além do nome do contato |
| P17 avaliações | span do RPC com contagem | `treinamento.correcao_promovida` (id do feedback e do treinamento) | pergunta e correção podem citar cliente — fora de log |
| P18 escopos | `origem_escopos` já existe; nova contagem de usuários migrados | `tenant_user.permissoes_migradas` **por usuário** (mudança de permissão é evento crítico, 08 §4.2) | nenhum token; escopos não são segredo |
