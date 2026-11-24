# ADR — Intermediário de webhooks de provedores (Evolution, Instagram, Telegram)

**Status:** Proposto — **não implementado** (verificado em 2026-11-24)
**Data:** 2026-11-24
**Substitui, na parte de entrada de webhooks:** `doc_dev/arquitetura/00-planejamento-adapters-grpc.md` (repo raiz) e `docker/adapters/README.md`.
**Relaciona-se com:** `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`, `doc_dev/planejamento/02-fases-desenvolvimento.md`.

---

## 1. Contexto

- O **Evolution Go é um gateway compartilhado** entre dev e prod. Ele não faz parte do sistema: recebe as mensagens do WhatsApp e as repassa por webhook ao sistema, que processa.
- Hoje a URL de webhook é **gravada por instância** no Evolution, pelo `data_whatsapp` do ambiente que cria ou conecta a instância (`WEBHOOK_INGRESS_URL` por ambiente, em `docker/stack/<env>.vars`).
- Estado verificado em 2026-11-24:
  - Existe **uma** instância no Evolution (id 181). Ela pertence ao banco da **dev**. O banco da **prod** tem zero instâncias.
  - A rota da prod (`172.17.0.1:9211`) responde a partir do container do Evolution, e a da dev também (`webhook_ingress:9200`).
- Problemas que um ponto único de entrada resolve:
  - **Roteamento:** a URL depende de qual ambiente conectou a instância. Não há regra explícita de qual ambiente é dono de cada instância.
  - **Acoplamento:** a rede `evolution_net` é compartilhada, então o nome `webhook_ingress` resolve para os dois ambientes. Isso já causou webhooks de dev caindo no ingress de prod em 2026-11-22.
  - **Novos canais:** Instagram e Telegram não têm onde entrar sem repetir o mesmo desenho por provedor.
- Divergência entre docs, a ser resolvida por este ADR:
  - `docker/adapters/README.md` (19/11) e `doc_dev/arquitetura/00-planejamento-adapters-grpc.md` (18/11) descrevem um **adapter separado**, com entrada por gRPC.
  - `doc_dev/planejamento/13` (fonte de verdade de mensageria) mantém a normalização **no `webhook_ingress`** e registra o `messaging_gateway` como removido.

## 2. Decisão proposta

1. **Um intermediário de borda por provedor, em HTTP** (provisoriamente `provider-edge`). Ele recebe o webhook nativo do provedor e valida a origem (token ou assinatura do próprio provedor). Depois normaliza o evento para o **evento universal** do sistema, que já existe em `infrastructure_messaging`, e encaminha ao ambiente dono.
2. **Roteamento por instância, sem fan-out.** Uma tabela `provider + instance_id → ambiente` define o destino. Cada evento vai **só** para o ambiente dono. Enviar para os dois ambientes duplicaria o processamento e é proibido.
3. **Entrada por HTTP, como hoje.** gRPC fica apenas entre o intermediário e o ingress interno, se for necessário. Isso substitui a entrada por gRPC dos docs de adapters.
4. **Instalação junto ao Evolution**, na mesma VPS, com componente próprio de infra (`docker/evolution` ou `docker/edge`). Mudanças seguem `deploy-infra.yml`, com aprovação do environment `prod` (regra R-D1).
5. **Canais novos (Instagram, Telegram)** entram como uma nova implementação do normalizador. O `webhook_ingress` já tem o registry de normalizadores (OCP), então o núcleo não muda.

## 3. Consequências

- Os ambientes deixam de depender de nome compartilhado na `evolution_net` e de porta por ambiente.
- Surge um ponto de falha novo, o intermediário. Ele precisa de healthcheck, métricas e logs estruturados desde o início (princípio de observabilidade do projeto).
- A instância existente (id 181) precisará ter a URL trocada para o intermediário, numa janela controlada e com ensaio em dev.

## 4. Estado atual (verificado)

| Item | Situação |
|---|---|
| Intermediário (`provider-edge`) | **Não implementado.** Não há código, Dockerfile nem compose. |
| `webhook_ingress` por ambiente | Implementado. Normaliza eventos e aplica rate limit. A cota passou a contar só mensagens (commit `5aceaf21`). |
| `WEBHOOK_INGRESS_URL` por ambiente | Implementado. Correto para a instância existente (dev). |
| Roteamento por instância | **Não implementado.** Hoje a URL é gravada por instância pelo ambiente que conecta. |
| Nomes de instância sem namespace | **Risco aberto.** Num gateway compartilhado, dev e prod podem gerar o mesmo nome. |
| Rota da prod a partir do Evolution | Verificada: responde 200 em `172.17.0.1:9211/health`. |

## 5. Pendências para implementação

1. Desenhar o contrato do evento universal de borda (reaproveitar `infrastructure_messaging`).
2. Criar o app/crate `provider_edge`, com Dockerfile e compose de infra.
3. Criar a tabela de roteamento `provider + instance_id → ambiente` e migrar a instância 181.
4. Definir namespace de nome de instância por ambiente (evita colisão no gateway compartilhado).
5. Testes de contrato no CI. Ensaio em dev. Só depois, prod pelo fluxo de infra, com aprovação.

## 6. Referências

- `doc_dev/planejamento/13-camada-de-abstração-de-mensageria.md`
- `doc_dev/planejamento/02-fases-desenvolvimento.md`
- `doc_dev/arquitetura/00-planejamento-adapters-grpc.md` (repo raiz)
- `docker/adapters/README.md`
