# ADR — Intermediário de webhooks de provedores (Evolution, Instagram, Telegram)

**Status:** Implementado no repositório (código, compose e workflow). **Ainda não ativo:** falta o primeiro `deploy-infra` (aprovação do environment `prod`) e o cutover das instâncias.
**Data:** 2026-11-24
**Substitui, na parte de entrada de webhooks:** `doc_dev/arquitetura/00-planejamento-adapters-grpc.md` (repo raiz) e `docker/adapters/README.md`.
**Relaciona-se com:** `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`, `doc_dev/planejamento/02-fases-desenvolvimento.md`.

---

## 1. Contexto

- O **Evolution Go é um gateway compartilhado** entre dev e prod. Ele não faz parte do sistema: recebe as mensagens do WhatsApp e as repassa por webhook ao sistema, que processa.
- A URL de webhook é **gravada por instância** no Evolution, pelo `data_whatsapp` do ambiente que cria ou conecta a instância. Esse ambiente é o **dono** da instância.
- Estado verificado em 2026-11-24:
  - Existe **uma** instância no Evolution (id 181). Ela pertence ao banco da **dev**. O banco da **prod** tem zero instâncias.
  - A rota da prod (`172.17.0.1:9211`) responde a partir do container do Evolution, e a da dev também (`webhook_ingress:9200`).
- Problemas que o intermediário resolve:
  - **Acoplamento:** a rede `evolution_net` é compartilhada, então o nome `webhook_ingress` resolve para os dois ambientes. Isso já causou webhooks de dev caindo no ingress de prod em 2026-11-22.
  - **Ponto único de entrada:** Instagram e Telegram precisam entrar pelo mesmo lugar, sem repetir o desenho por provedor.
- Divergência entre docs, resolvida por este ADR:
  - `docker/adapters/README.md` (19/11) e `doc_dev/arquitetura/00-planejamento-adapters-grpc.md` (18/11) descreviam um adapter com entrada por **gRPC** e normalização na borda.
  - `doc_dev/planejamento/13` (fonte de verdade de mensageria) mantém a **normalização no `webhook_ingress`**.

## 2. Decisão

1. **Intermediário transparente, em HTTP** (`provider_edge`). Ele recebe o webhook nativo do provedor e o repassa ao `webhook_ingress` do ambiente indicado. **Não lê o corpo, não normaliza, não autentica o provedor.** A autenticação continua no `webhook_ingress`, pela apikey ou token da instância. Isso mantém a normalização onde o doc 13 manda.
2. **Roteamento pelo caminho, sem tabela e sem fan-out.** A URL gravada na instância carrega o destino: `http://provider_edge:8088/{ambiente}/webhook/{provedor}/{tenant}/{instancia}`. Como quem registra a instância é o ambiente dono, a URL já aponta para o ambiente certo. Uma tabela seria redundante e mais um item para manter. Enviar para os dois ambientes duplicaria o processamento e é proibido.
   - O ambiente desconhecido responde 404, sem repassar nada.
   - O destino de cada ambiente vem de `PROVIDER_EDGE_DESTINOS` (ex.: `dev=http://webhook_ingress:9200,prod=http://172.17.0.1:9211`).
3. **Entrada por HTTP, como hoje.** Nenhum gRPC na entrada. Status e corpo da resposta do ingress são repassados ao provedor. Assim, uma recusa (401, 429, 5xx) é reentregue pela Evolution exatamente como se o ingress tivesse sido chamado direto.
4. **Instalação junto ao Evolution**, em `docker/evolution/compose.yml`, na `evolution_net`, sem porta publicada. A imagem é gerada no próprio workflow, a partir do mesmo `docker/server/Dockerfile` do servidor, e fixada por sha. O deploy segue `deploy-infra.yml`, com aprovação do environment `prod` (regra R-D1).
5. **Canais novos (Instagram, Telegram)** usam o mesmo caminho: `/{ambiente}/webhook/{provedor}/...`. A parte nova fica no normalizador do `webhook_ingress` (registry, OCP). O intermediário não muda.
6. **Tamanho do corpo:** o mesmo teto do ingress (32 MB). A Evolution manda mídia em base64 dentro do webhook. Um teto menor cortaria mensagens reais.
7. **Timeout de 10 s para o destino.** Acima disso, o intermediário responde 504 e o provedor reentrega.

## 3. Consequências

- Os ambientes deixam de depender de nome compartilhado na `evolution_net` e de porta por ambiente. Cada ambiente é alcançado por um destino explícito.
- Surge um ponto de falha novo, o intermediário. Ele tem healthcheck (`/health`), logs estruturados em JSON (sem corpo de webhook) e limite de memória de 128 MB.
- Se o intermediário cair, o Evolution reentrega. Por isso a reentrega do provedor é parte do desenho, não um acaso.
- As instâncias existentes **só mudam de URL depois do cutover** (seção 5). Até lá, o caminho antigo, direto ao ingress, continua funcionando. Por isso o código pode entrar no `dev` sem quebrar nada.

## 4. Estado atual

| Item | Situação |
|---|---|
| `provider_edge` (crate, `server/apps/provider_edge`) | **Implementado**, com testes de rota: repasse ao ambiente do caminho (status, corpo, query e apikey intactos), 404 para ambiente desconhecido ou caminho sem ambiente, 502 com destino fora do ar e 504 com destino lento. |
| Imagem (`docker/server/Dockerfile`) | **Corrigido em 2026-11-24.** O binário `provider_edge` não era copiado para a imagem final. O primeiro deploy-infra teria subido o container com "executable not found", reprovado no smoke e voltado ao bundle anterior. A CI (job `infra`) agora confere que todo app chamado por `command:` em algum compose está no Dockerfile, e valida o compose do Evolution. |
| OTLP do `provider_edge` | Desligado (`OTEL_SDK_DISABLED=true`): o serviço só está na `evolution_net`, sem rota para o collector. Os logs JSON do stdout chegam ao Loki pelo promtail. |
| Compose (`docker/evolution/compose.yml`, serviço `provider_edge`) | **Implementado.** Só sobe com `PROVIDER_EDGE_IMAGE` no env do Evolution. |
| Workflow `deploy-infra.yml` (job `build-provider-edge`) | **Implementado.** Gera a imagem por sha e a passa ao `deploy-infra.sh evolution`. |
| Primeiro deploy de infra | **Pendente de aprovação** do environment `prod`. É o único passo que depende de decisão humana. Disparar de novo depois da correção da imagem: um run anterior a ela reprovaria. |
| `webhook_ingress` por ambiente | Implementado. Normaliza eventos e aplica rate limit. A cota conta só mensagens (`5aceaf21`). O 429 é log-only por padrão (`fix2`). |
| Checagem de nome único no gateway | Implementada em `data_whatsapp`: recusa criação se o nome já existe no Evolution, e falha fechada se a consulta falhar. |
| Cutover das instâncias para o intermediário | **Pendente.** Depende do primeiro deploy de infra. |
| Rota da prod a partir do Evolution | Verificada: responde 200 em `172.17.0.1:9211/health`. |

## 5. Cutover (passos, depois do deploy de infra)

Feito em dev primeiro. Prod só depois de a dev ficar estável.

1. Confirmar que o `provider_edge` está `healthy` (`docker ps`, healthcheck em `/health`).
2. Trocar a URL base do webhook por ambiente. As duas mudanças já estão escritas no repositório, comentadas:
   - dev: descomentar `WEBHOOK_INGRESS_URL=http://provider_edge:8088/dev` em `docker/stack/dev.vars` (o `.vars` vence o `.env` e o default do `docker-compose.base.yml`). Sai pelo `deploy-dev` no push da `dev`.
   - prod: trocar o valor **fixo** em `docker/stack/prod.override.yml` por `http://provider_edge:8088/prod` (hoje `172.17.0.1:9211`). Só chega à prod numa tag `v*.*.*` aprovada (`deploy-prod`). Merge na `dev` ou na `main` não muda a prod sozinho.
   - Não ativar nenhuma das duas antes de o passo 1 dar `healthy`: o Evolution chamaria um host inexistente e o ambiente pararia de receber mensagens.
3. Reconectar a instância 181 pelo fluxo de reconciliação do `data_whatsapp` (`connect` regrava a URL). Conferir no Evolution que a URL passou a ser `http://provider_edge:8088/dev/...`.
4. Verificar um webhook real: `docker logs smart-core-v2-dev-webhook_ingress-1` deve mostrar o evento; `smartcore-provider-edge` deve mostrar `webhook repassado`.
5. Só então repetir para prod com a instância de prod (quando existir).

## 6. Pendências

1. **Aprovação do primeiro `deploy-infra`** (environment `prod`). Ação humana, prevista na regra R-D1.
2. **Cutover** da instância 181 (passos da seção 5).
3. **Valor de `WEBHOOK_RATE_LIMIT_ENFORCE` no secret de prod** (`true` hoje, conferido no container em 2026-11-24; na dev a chave está ausente, então vale o default `false`). Decisão: alinhar a prod ao default do código, `false` (log-only), pelo mesmo motivo do `fix2`: o 429 faz a Evolution desistir depois de 4 reentregas e a mensagem se perde. Os `.env.example` já foram alinhados. Ação do dono: editar o secret `ENV_FILE_B64` do environment `prod`. Vale no próximo deploy de prod. Hoje a prod tem zero instâncias, então não há perda em curso.
4. **Sem namespace de nome de instância.** A checagem de nome único resolve a colisão, mas o nome continua sendo texto livre. Namespace por ambiente exigiria renomear instâncias existentes e fica como melhoria futura.

## 7. Referências

- `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`
- `doc_dev/planejamento/02-fases-desenvolvimento.md`
- `doc_dev/arquitetura/00-planejamento-adapters-grpc.md` (repo raiz)
- `docker/adapters/README.md`
- `infra/deploy/deploy-infra.sh`, `.github/workflows/deploy-infra.yml`
