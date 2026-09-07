---
type: plan
name: "Painel CRM e campos do cartão"
planSlug: painel-crm-e-campos-do-cartao
description: "O laço da IA está aberto: ela já recebe quais campos faltam e como extraí-los, mas o ResponderResponse não tem por onde devolver o valor — pergunta, o cliente responde, o valor é descartado, e na mensagem seguinte ela pergunta de novo. O filtro do que vai ao prompt é obrigatorio, não extrair_automaticamente: a coluna que existe para isso nunca é lida. O catálogo de campos é somente-leitura em produção, então nenhum tenant tem ou pode ter um campo. E o atendimento só nasce de fora para dentro — não há como iniciar conversa com um cliente cadastrado."
summary: "Delta de três pedidos de produto medidos contra o código em 2026-09-07. Dois dos três já estavam planejados: conversa em painel é N9 E12, catálogo de campos é N9 E13 — ambos precisados no plano da N9 no mesmo levantamento. Sobram quatro blocos: C1 write-back da IA com cinco guardas, C2 filtro de extração correto, C3 IniciarAtendimento, C4 contato editável."
status: filled
progress: 0
generated: "2026-09-07"
scaffoldVersion: "2.0.0"
agents:
  - type: "architect-specialist"
    role: "Contrato do Responder e o write-back que ele nunca teve"
  - type: "ai-specialist"
    role: "Saída estruturada no ia_engine: extrair sem inventar, omitir sem punição"
  - type: "backend-specialist"
    role: "As cinco guardas de gravação, IniciarAtendimento e escrita de contato"
  - type: "database-specialist"
    role: "Upsert condicional e a distinção entre valor apagado e nunca preenchido"
  - type: "frontend-specialist"
    role: "Iniciar atendimento a partir do contato; cadastro e vínculo com cliente"
  - type: "test-writer"
    role: "Regressão das guardas e prova de que nenhum valor vaza em log"
phases:
  - id: "phase-p"
    name: "Planning"
    prevc: "P"
    agent: "architect-specialist"
    status: "pending"
  - id: "phase-r"
    name: "Review"
    prevc: "R"
    agent: "ai-specialist"
    status: "pending"
  - id: "phase-e"
    name: "Execution"
    prevc: "E"
    agent: "backend-specialist"
    status: "pending"
    required_sensors: [rust-rapido, flutter-analise-testes, ia-engine-testes]
    required_artifacts: [handoff-summary]
  - id: "phase-v"
    name: "Validation"
    prevc: "V"
    agent: "test-writer"
    status: "pending"
  - id: "phase-c"
    name: "Confirmation"
    prevc: "C"
    agent: "documentation-writer"
    status: "pending"
---

# Painel CRM e campos do cartão

> **Este plano é só o delta.** Dos três pedidos que o originaram, **dois já
> estavam planejados**: a conversa em painel ao lado do quadro é **N9 E12** e o
> catálogo de campos personalizados é **N9 E13** — ambos precisados no plano da
> N9 em 2026-09-07, no mesmo levantamento que gerou este. Aqui ficam os quatro
> blocos que nenhum plano cobria.

## Artefatos detalhados

- **Plano completo** (verdade técnica, com arquivo:linha):
  [plano_completo_painel-crm-e-campos-do-cartao.md](./painel-crm-e-campos-do-cartao/plano_completo_painel-crm-e-campos-do-cartao.md)
- **Documentação auxiliar**:
  [info_aux_painel-crm-e-campos-do-cartao.md](./painel-crm-e-campos-do-cartao/info_aux_painel-crm-e-campos-do-cartao.md)

## Fontes de requisito

- [33 — O painel como CRM](../../doc_dev/planejamento/33-painel-como-crm-atendimento-ativo-e-campos-do-cartao.md) — **a medição dos três pedidos contra o código**
- [34 — Plano: painel CRM e campos do cartão](../../doc_dev/planejamento/34-plano-painel-crm-e-campos-do-cartao.md) — origem deste plano

## O achado que reordena tudo

`ResponderRequest` leva `campos_pendentes` com `slug`, `nome`, `descricao` e
`hint` — a IA **já é instruída** sobre qual campo falta e como extraí-lo.
`ResponderResponse` tem quatro campos e **nenhum carrega valor extraído**.

O port documenta a ausência como se fosse dado da natureza: *"o contrato do
Responder não devolve campos extraídos, então não há write-back aqui"*
(`ports/atendimento.rs:435`).

Não é recurso faltando — é comportamento errado: a IA pergunta, o cliente
responde, o valor é descartado, o campo segue pendente, e **na mensagem
seguinte ela pergunta de novo**. E a N9 E13 planeja exibir a origem `IA` com
barra de confiança: uma origem que nada no sistema sabe gravar.

## Decisões de produto já tomadas — não reabrir

| Tema | Decisão |
|---|---|
| Piso de confiança para gravar campo | **O mesmo limiar do D1**; enquanto ele não existir, 0.8 constante |
| IA sobrescrever valor humano | **Nunca** — nem o corrigido, nem o apagado |
| Slug fora do catálogo | **Descartado.** O LLM não define o esquema |
| Valor de tipo inválido | **Descartado**, nunca coagido a texto |
| Bot na conversa iniciada à mão | Nasce **desligado**; o caminho de volta é o D3, já entregue |
| Contato já em conversa aberta | **Reaproveita** o atendimento, não duplica |
| Valor de campo em log ou auditoria | **Nunca** — auditar qual campo, não o quê |

## Entregas

| Bloco | Lacuna | O que fazer |
|---|---|---|
| **C1** | doc 33 §4.1 🚨 | `campos_extraidos` na `ResponderResponse` + gravação com **cinco guardas**. *O item de maior valor, e não estava em nenhum pedido* |
| **C2** | doc 33 §4.2 | `extrair_automaticamente` decide o que vai ao prompt, no lugar de `obrigatorio` |
| **C3** | doc 33 §4.5 | `IniciarAtendimento` a partir de contato ou cliente, reusando a invariante de um ativo por contato |
| **C4** | doc 33 §2 | Contato deixa de ser somente-leitura: criar, editar e vincular a cliente |

## Sequência

```
C2 → C1        (os dois mexem no prompt; C2 é barato e precede a N9 E13)
C4 → C3        (iniciar conversa com quem não está cadastrado exige cadastrar)
```

C1/C2 e C3/C4 são independentes e podem correr em paralelo.

**Dependência que importa fora daqui: N9 E13 depende de C1.** Sem o write-back,
a E13 constrói uma barra de confiança que nunca aparece.

## Riscos principais

- 🚨 **Alucinação grava dado errado na ficha do cliente.** O schema Pydantic
  valida forma, não verdade: um slug inexistente com valor inventado é JSON
  perfeitamente válido. Quem protege são as cinco guardas do servidor.
- 🚨 **Disparo ativo derruba o número do tenant.** A evolution-go é whatsmeow:
  `POST /send/text` aceita qualquer JID, **sem a janela de 24 h** da Cloud API.
  Trivial de implementar, curto para ser denunciado. Mitigação é de produto.
- 🚨 **Valor de campo é PII livre** — pode ser CPF, endereço, diagnóstico.
  `skip_all` em todo o caminho de C1, e teste que assere sobre o registro.
- ⚠️ **Não seguir o `ref_evolution_go.md` no envio.** A linha 874 daquele
  arquivo traz `POST /message/sendText/{instance}`, formato da **Evolution v2**,
  que não existe aqui. O real é `POST /send/text` (`provider.rs:446`).
- **Sem risco de migração:** `criar` e `upsert` de campo só são chamados por
  testes — nenhum tenant tem, ou pode ter, um campo personalizado. É a hora
  mais barata que existirá para acertar o formato.

## Definition of Done

- [ ] A IA extrai um campo declarado na conversa; ele aparece na ficha com origem `IA` e confiança.
- [ ] A IA **para** de perguntar um campo depois que ele foi preenchido.
- [ ] Valor corrigido por humano não é sobrescrito; valor apagado não é repreenchido.
- [ ] Campo com `extrair_automaticamente = false` nunca chega ao prompt.
- [ ] Valor de tipo inválido é descartado, nunca coagido a texto.
- [ ] Nenhum valor de campo em log ou auditoria — provado por teste.
- [ ] Atendimento criado a partir de um contato cai numa coluna do quadro, com o bot desligado e atribuído a quem criou.
- [ ] Contato já em conversa aberta reaproveita o atendimento, não duplica.
- [ ] Disparo ativo é auditado com autor e respeita o teto diário.
- [ ] Contato pode ser cadastrado, editado e vinculado a um cliente.
- [ ] Sensores `rust-rapido`, `flutter-analise-testes` e `ia-engine-testes` verdes.

## Fora de escopo

- **Conversa em painel ao lado do quadro** → N9 **E12**.
- **Catálogo de campos, tipos, opções, ficha e cartão** → N9 **E13**.
- **Preview e foto no cartão** → N9 E11.
- Demais frentes: N10, N11, N12, `cadastro-retomavel-e-pagamento` e
  `regras-do-bot-e-permissoes`.
