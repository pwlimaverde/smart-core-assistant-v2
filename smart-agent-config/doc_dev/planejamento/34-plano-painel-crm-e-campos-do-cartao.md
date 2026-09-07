# 34 — Plano: painel CRM e campos do cartão

> **Origem:** [doc 33](./33-painel-como-crm-atendimento-ativo-e-campos-do-cartao.md),
> que mediu os três pedidos contra o código e contra os planos existentes.
>
> **Este plano é só o delta.** A conversa no painel (P2) é **N9 E12** e o
> catálogo de campos (P3) é **N9 E13** — ambos já precisados no plano da N9 em
> 2026-09-07. O que sobra são quatro blocos que nenhum plano cobre.

---

## O que este plano resolve

| Bloco | Entrega | Por que existe |
|---|---|---|
| **C1** | A IA devolve o campo que extraiu | Hoje ela pergunta, o cliente responde, e o valor é jogado fora |
| **C2** | `extrair_automaticamente` decide o que vai ao prompt | Hoje quem decide é `obrigatorio`, que é outra coisa |
| **C3** | `IniciarAtendimento` a partir de um cliente | O atendimento só nasce de fora para dentro |
| **C4** | Contato deixa de ser somente-leitura | Sem cadastrar contato não há de quem partir |

**C1 é o item de maior valor do conjunto** — e não estava em nenhum pedido.
Sem ele, N9 E13 entrega um catálogo de campos que só se preenche à mão, e
constrói uma barra de confiança para uma origem que nada sabe gravar.

---

## C1 — Fechar o laço: a IA preenche o campo

### O defeito

`ResponderRequest` leva `campos_pendentes` com `slug`, `nome`, `descricao` e
`hint`; `ResponderResponse` não tem por onde devolver o valor
(`ai_engine.proto:131`). O port documenta a ausência como se fosse um dado da
natureza: *"o contrato do Responder não devolve campos extraídos, então não há
write-back aqui"* (`ports/atendimento.rs:435`).

O efeito em produção não é ausência de recurso: é a IA perguntando a mesma
coisa em toda mensagem, porque a resposta do cliente nunca vira valor.

### Contrato (aditivo)

```proto
message CampoExtraido {
  string slug = 1;
  string valor_json = 2;  // já na forma tipada do campo (doc 33 §5)
  double confianca = 3;
}

message ResponderResponse {
  string resposta_texto = 1;
  bool   transferir_atendimento = 2;
  string fluxo_transferencia = 3;
  double confiabilidade = 4;
  repeated CampoExtraido campos_extraidos = 5;  // novo
}
```

No `ia_engine`: o prompt do Responder já recebe os pendentes com a `hint`.
Passa a instruir a devolver **só o que foi dito pelo cliente** e a **omitir o
campo quando não souber** — nunca inferir, nunca completar. Um campo omitido é
o resultado certo na maioria das mensagens.

### Gravação — as cinco guardas, nesta ordem

Novo RPC interno `GravarCamposExtraidos(atendimento_id, [{slug, valor,
confianca}], mensagem_origem_id)` no `data_postgres`, chamado pelo worker
depois da resposta. Cada item passa por:

1. **O slug existe no catálogo aplicável e está ativo.** Slug alucinado é
   descartado — o LLM não define o esquema.
2. **`extrair_automaticamente = true`.** Um campo marcado para não ser extraído
   não é gravado nem que a IA devolva.
3. **O valor é válido para o `tipo`** (e, em `lista`, cada id existe em
   `opcoes`). Inválido é descartado com contagem, não gravado como texto.
4. **`confianca >= limiar do tenant`** — o mesmo limiar do **D1** de
   `regras-do-bot-e-permissoes`. Um número por tenant para "quando confio na
   IA"; dois seriam duas verdades sobre a mesma coisa. Enquanto o D1 (deploy 2)
   não entrega o limiar configurável, C1 usa o padrão 0.8 como constante.
5. **Não sobrescreve humano, nem repreenche o que humano apagou:**

```sql
ON CONFLICT (tenant_id, atendimento_id, campo_id) DO UPDATE
   SET valor = EXCLUDED.valor, origem = 'IA', confianca = EXCLUDED.confianca,
       mensagem_origem_id = EXCLUDED.mensagem_origem_id,
       data_atualizacao = NOW()
 WHERE atu_valor_campo.editado_por_id IS NULL
   AND atu_valor_campo.valor <> 'null'::jsonb
```

`editado_por_id` existe na tabela e **hoje nunca é gravado**; passa a ser
gravado na edição manual (N9 E13). `valor = 'null'::jsonb` é o valor apagado
de propósito — quem apagou já viu a conversa e discordou da IA.

### Observabilidade & Auditoria

- **Auditoria:** `campo_personalizado.preenchido_pela_ia` — slug e confiança.
  **Nunca o valor**: é livre, pode ser CPF, endereço ou diagnóstico.
- **Log:** span `ia.campos_extraidos` com recebidos, gravados e descartados
  **por motivo** (slug desconhecido, tipo inválido, abaixo do piso, humano no
  caminho). Esse detalhamento é o instrumento para calibrar o piso — sem ele,
  "a IA não preenche" é indistinguível de "a IA preenche errado".
- **Nunca em log:** o `valor_json`.

### Testes

Slug inexistente descartado · valor de tipo errado descartado · opção fora de
`opcoes` descartada · abaixo do piso descartado · valor humano preservado ·
valor apagado por humano não repreenchido · campo com
`extrair_automaticamente = false` ignorado.

---

## C2 — `extrair_automaticamente` decide o que vai ao prompt

Em `resolver_campos_atendimento` (`adapters/atendimento.rs:1469`), trocar o
filtro de pendentes:

```rust
None if def.obrigatorio            => pendentes.push(...)   // hoje
None if def.extrair_automaticamente => pendentes.push(...)   // passa a ser
```

`obrigatorio` volta a ser o que o nome diz: **regra de tela**, não regra de
prompt — impede concluir o atendimento sem o campo, e nada mais.

**Sem risco de migração:** nenhum tenant tem campo personalizado (doc 33 §4.3),
porque não existe caminho para criar um. A troca não altera o comportamento de
ninguém hoje; altera o comportamento de todo mundo depois da N9 E13. É por isso
que precisa entrar **antes** dela, e não depois.

Entra junto com C1: os dois mexem no que a IA vê.

---

## C3 — Atendimento ativo: falar primeiro

### RPC

`IniciarAtendimento(contato_id | telefone+nome, fluxo_id, etapa_id?,
departamento_id?, assunto?, primeira_mensagem?)`, escopo `atendimentos:write`.

### Regras

- **Reusa a invariante de um ativo por contato.** `buscar_ou_criar`
  (`adapters/atendimento.rs:660`) já busca o atendimento ativo antes de criar.
  Se já existe conversa aberta com aquele contato, o RPC devolve a existente
  com `ja_existia = true` e a tela **abre** em vez de criar um segundo cartão.
  Criar o segundo quebraria a invariante e duplicaria a fila.
- **Define fluxo e etapa explicitamente.** A ingestão cria com
  `(None, None, None)` e o fluxo é preenchido depois por `COALESCE`
  (`atendimentos.rs:624`). Um atendimento sem etapa **não aparece em nenhuma
  coluna do quadro** — nasceria invisível.
- **`bot_pode_atender = false` na criação manual.** Alguém decidiu falar com
  esse cliente; o robô não entra no meio de uma conversa que uma pessoa
  começou. O caminho de volta já existe: `DefinirBotDaConversa` (D3, entregue).
- **`atendente_humano_id` = quem criou.** Quem inicia, atende.
- **`primeira_mensagem`**, quando vier, encadeia `SendOutboundMessage` na mesma
  ação — senão o cartão nasce mudo e alguém precisa lembrar de escrever.

### O risco que não é técnico

A evolution-go é whatsmeow: `POST /message/text` aceita qualquer JID, **sem a
janela de 24 h** da Cloud API. Iniciar conversa é tecnicamente trivial — e é o
caminho mais curto para o número do tenant ser denunciado e bloqueado.

Mitigação: teto diário por tenant, auditoria por autor, e recusa clara quando a
instância não está conectada (em vez de enfileirar um envio que nunca sai).

**Auditoria:** `atendimento.iniciado_manualmente` — autor, contato, fluxo.
**Não** o texto da mensagem.

### Cliente

Botão "Iniciar atendimento" no quadro e na tela de contatos. Seletor de contato
com busca (a busca de contatos já é server-side), seletor de fluxo e etapa
inicial, campo opcional de primeira mensagem.

---

## C4 — Contato deixa de ser somente-leitura

`CriarMeuContato`, `AtualizarMeuContato`, `VincularContatoCliente`,
`DesvincularContatoCliente`. A tela `contatos_page.dart` ganha criar e editar;
o M2M `oraculo_cliente_contatos` já existe desde a migração 0004.

**Normalizar o telefone antes de gravar.** A chave é
`UNIQUE (tenant_id, telefone)`: sem normalização, `+55 11 9…` e `5511 9…` viram
dois contatos, e o mesmo cliente ganha dois atendimentos que nunca se
encontram. Reusar a normalização já usada na ingestão — não escrever uma
segunda.

**Auditoria:** `contato.criado`, `contato.atualizado`,
`contato.vinculado_cliente`.

---

## Sequência

```
C2 → C1        (os dois mexem no prompt; C2 é barato e precede a N9 E13)
C4 → C3        (iniciar conversa com quem não está cadastrado exige cadastrar)
```

C1/C2 e C3/C4 são independentes entre si e podem correr em paralelo.

**Dependências para fora:**
- C1 usa o limiar de confiança do **D1** (`regras-do-bot-e-permissoes`);
  enquanto ele não existe, usa 0.8 como constante.
- C3 usa `DefinirBotDaConversa` do **D3** — já entregue.
- **N9 E13 depende de C1** para que a origem `IA` que ela exibe seja
  alcançável. C1 antes de E13, ou E13 entrega uma barra que nunca aparece.

---

## Riscos

| Risco | Mitigação |
|---|---|
| 🚨 **Alucinação grava dado errado na ficha do cliente** | As cinco guardas de C1, em ordem; piso de confiança; e o prompt instruído a omitir, não a inferir |
| 🚨 **Disparo ativo derruba o número do tenant** | Teto diário, auditoria por autor, recusa se a instância não estiver conectada |
| Prompt cresce sem limite com muitos campos | Teto de 50 campos por escopo (N9 E13); todo pendente entra em toda mensagem |
| Duplicidade de contato por telefone não normalizado | Reusar a normalização da ingestão, nunca escrever a segunda |
| Atendimento manual nasce fora de qualquer coluna | Fluxo e etapa obrigatórios no RPC, validados no servidor |

---

## Definition of Done

- [ ] A IA extrai um campo declarado na conversa e ele aparece na ficha com
      origem `IA` e a confiança.
- [ ] A IA **para** de perguntar um campo depois que ele foi preenchido.
- [ ] Valor corrigido por humano não é sobrescrito na mensagem seguinte.
- [ ] Valor apagado por humano não é repreenchido.
- [ ] Campo com `extrair_automaticamente = false` nunca chega ao prompt.
- [ ] Nenhum valor de campo em log ou auditoria — provado por teste.
- [ ] Atendimento criado a partir de um contato cai numa coluna do quadro, com
      o bot desligado e atribuído a quem criou.
- [ ] Contato já em conversa aberta reaproveita o atendimento, não duplica.
- [ ] Contato pode ser cadastrado, editado e vinculado a um cliente.
- [ ] Sensores `rust-rapido` e `flutter-analise-testes` verdes.

## Fora de escopo

- **Conversa em painel ao lado do quadro** → N9 E12 (precisada em 2026-09-07).
- **Catálogo de campos, tipos, opções e ficha** → N9 E13 (idem).
- **Preview e foto no cartão** → N9 E11.
- Tudo o mais já coberto por N10, N11, N12, `cadastro-retomavel-e-pagamento` e
  `regras-do-bot-e-permissoes`.
