# Documentação Auxiliar — Painel CRM e campos do cartão

> Gerado em: 2026-09-07
> Plano canônico: `.context/plans/painel-crm-e-campos-do-cartao.md`
> Plano completo: `.context/plans/painel-crm-e-campos-do-cartao/plano_completo_painel-crm-e-campos-do-cartao.md`
> Fonte de requisito: `doc_dev/planejamento/33-painel-como-crm-atendimento-ativo-e-campos-do-cartao.md`

---

## Triagem da central local (`doc_dev/libs/`)

| Lib | Stack | Manifesto | Doc local | Verificado | Decisão |
|---|---|---|---|---|---|
| `langchain` | python | `>=1.0` | 1.0.0+ ✅ | 2026-07-06 | **USAR LOCAL** — cobre `with_structured_output` e Pydantic v2 nativo |
| `pydantic` | python | `>=2.9` | 2.7.1 ✅ | 2026-05-31 | **ATUALIZADO** — doc apontava versão *anterior* à do projeto |
| `sqlx` | rust | 0.9 | 0.9.0 ✅ | 2026-06-10 | **USAR LOCAL** (ver ressalva abaixo) |
| `tonic` / `prost` | rust | 0.14.6 / 0.14.3 | ✅ | 2026-06-04 / 06-18 | **USAR LOCAL** — uso é campo aditivo em mensagem existente |
| `tracing` / `serde` | rust | 0.1.40 / 1.0 | ✅ | 2026-05-31 | **USAR LOCAL** |

**Ressalva do `sqlx`:** o doc local não cobre `JSONB` nem
`ON CONFLICT … DO UPDATE … WHERE`. Não foi motivo para Context7, porque nenhum
dos dois é API do sqlx: a cláusula `WHERE` no `DO UPDATE` é **PostgreSQL**, e a
ligação `serde_json::Value` ↔ `JSONB` em `query_as!` já está **provada no
próprio repositório** — `campos.rs:165` faz exatamente isso hoje, e compila
contra o cache offline. Evidência em código vale mais que doc de terceiro.

---

## Libs Python

### langchain (1.0+) — `doc_dev/libs/python/langchain.md`, verificado 2026-07-06

Relevante para **C1**:

- O shim `langchain_core.pydantic_v1` **foi removido**. Usar `pydantic.BaseModel`
  (v2) direto, inclusive em `with_structured_output`.
- LCEL por pipe (`prompt | llm | parser`) é o padrão;
  `StrOutputParser`/`PydanticOutputParser` em `langchain_core.output_parsers`.
- Credenciais dos provedores vêm de Pydantic Settings, nunca de globais.

### pydantic (2.13.4) — `doc_dev/libs/python/pydantic.md`, **atualizado em 2026-09-07**

O doc local apontava **2.7.1** enquanto o `pyproject.toml` do `ia_engine` já
exigia `>=2.9` — a central estava atrás do próprio projeto. Corrigido para
2.13.4 (última estável, 2026-05-06).

**Entre 2.7 e 2.13 nada quebra** no que este plano usa (`BaseModel`, `Field`,
`model_validate`, `model_json_schema`). As rupturas do período ficaram fora do
caminho: remoção do Python 3.8, `model_fields` acessado em instância (deprecado),
formato de campos do `create_model`, e comportamento de `serialize_as_any`.

Forma da saída estruturada do `Responder` (detalhe na §3 do doc local):

```python
class CampoExtraido(BaseModel):
    slug: str = Field(description="slug exato do campo pendente; nunca invente")
    valor_json: str = Field(description="valor na forma tipada do campo")
    confianca: float = Field(ge=0.0, le=1.0)
```

> ⚠️ **O schema restringe a forma, não a verdade.** Um `slug` inexistente e um
> valor inventado são JSON perfeitamente válido. A validação semântica é do
> servidor — é o que fazem as cinco guardas de C1.

---

## Libs Rust

Uso trivial e coberto pela central: campo aditivo em mensagem `prost`/`tonic`
existente, `serde_json::Value` para o `JSONB`, `tracing` conforme a política da
arquitetura de erros.

### PostgreSQL — upsert condicional (C1)

A guarda anti-sobrescrita não é código de aplicação, é cláusula de banco:

```sql
INSERT INTO atu_valor_campo
    (tenant_id, atendimento_id, campo_id, valor, origem, confianca, mensagem_origem_id)
VALUES ($1, $2, $3, $4, 'IA', $5, $6)
ON CONFLICT (tenant_id, atendimento_id, campo_id) DO UPDATE
   SET valor = EXCLUDED.valor,
       origem = 'IA',
       confianca = EXCLUDED.confianca,
       mensagem_origem_id = EXCLUDED.mensagem_origem_id,
       data_atualizacao = NOW()
 WHERE atu_valor_campo.editado_por_id IS NULL
   AND atu_valor_campo.valor <> 'null'::jsonb
RETURNING id
```

Dois detalhes que decidem o comportamento:

1. **`WHERE` no `DO UPDATE`.** Quando a condição é falsa, a linha existente é
   preservada e **nada é retornado** — `RETURNING` devolve zero linhas. Isso dá
   ao chamador o sinal de "não gravei" sem uma consulta extra.
2. **`'null'::jsonb` é um valor não-nulo.** Numa coluna `JSONB NOT NULL`, o
   literal JSON `null` é gravável e distinguível da ausência de linha. É o que
   permite separar *nunca preenchido* (sem linha) de *apagado de propósito*
   (linha com `'null'::jsonb`) sem acrescentar coluna.

---

## Serviços Externos

### evolution-go — envio de texto (C3)

> 🚨 **Armadilha confirmada.** O `ref_evolution_go.md` da N9 traz, na linha 874,
> um exemplo no formato da **Evolution API v2**:
> `POST /message/sendText/{instance}`. **Esse endpoint não existe aqui.** A
> fonte da verdade é `infrastructure_evolution/src/provider.rs`, e o contrato
> real é outro.

Contrato real, lido em `provider.rs:446` (`send_text`):

```
POST {base_url}/send/text
Header: apikey: <token da instância>        # SecretString, nunca logar
Body:   {"number": "<telefone>", "text": "<texto>"}
```

Retry já implementado no provider: até 3 tentativas, backoff a partir de 500 ms,
só para erro 5xx e `429`. Erro 4xx não é retentado.

Outros paths do mesmo provider, para referência de forma (todos `/…` diretos, sem
`{instance}` no path): `/message/presence`, `/message/markread`, `/message/react`,
`/message/downloadmedia`.

**Fato que decide o risco de C3:** a evolution-go é whatsmeow. `POST /send/text`
aceita qualquer JID — **não há a janela de 24 h nem o template obrigatório** da
WhatsApp Cloud API. Iniciar conversa com quem nunca escreveu é tecnicamente
trivial e operacionalmente perigoso: é o caminho curto para o número ser
denunciado e bloqueado. A mitigação é de produto (teto diário, auditoria por
autor), não técnica — o provider não vai impedir.

### Trello — modelo de campos personalizados (referência de design)

Fontes:
[Getting Started With Custom Fields](https://developer.atlassian.com/cloud/trello/guides/rest-api/getting-started-with-custom-fields/) ·
[Custom Fields REST API](https://developer.atlassian.com/cloud/trello/rest/api-group-customfields/)

| Aspecto | Trello |
|---|---|
| Tipos | `text`, `number`, `date`, `checkbox`, `list` — cinco, fechados |
| Definição | `name`, `type`, `pos`, `options[]`, `idModel` + `modelType: "board"` |
| Opção | `{"id": "...", "value": {"text": "High"}, "color": "red", "pos": 16384}` |
| Valor | `{"text":…}` · `{"number":"42"}` · `{"date": ISO}` · `{"checked":"true"}` · **`{"idValue": "<id da opção>"}`** |
| Limpar | `PUT` vazio; **não há endpoint de exclusão** |
| Teto | 50 definições por quadro |

**O que copiar** — os cinco tipos; valor tipado pela definição; **a lista guarda
o id da opção, nunca o rótulo** (renomear não pode reescrever cartão nenhum);
ordem explícita; e um teto.

**Onde divergir** — descrição é peça central (é a instrução da IA, no Trello
seria enfeite); lista é **múltipla** (interesse em produto não é excludente);
dois escopos (`GLOBAL` + `FLUXO`) em vez de um; e o valor limpo é **estado
semântico**, não ergonomia: a IA não pode repreencher o que um humano apagou.

O teto de 50, aqui, tem outra razão que no Trello: lá é ergonomia de tela, aqui
é **custo por mensagem** — todo campo pendente entra no prompt.

---

## Grupo C — Observabilidade e Auditoria (levantamento por bloco)

| Bloco | Spans / eventos | `audit_log` | Risco de vazamento |
|---|---|---|---|
| **C1** | `ia.campos_extraidos` — `recebidos`, `gravados`, `descartados_por_motivo` (slug desconhecido, tipo inválido, abaixo do piso, humano no caminho) | `campo_personalizado.preenchido_pela_ia` — **slug e confiança, nunca o valor** | 🚨 **alto** — `valor_json` é livre: pode ser CPF, endereço, diagnóstico. `skip_all` obrigatório; o valor não entra em span, log nem descrição de auditoria |
| **C2** | campo `pendentes_por_extracao` no span já existente de resolução | **sem evento de auditoria** — é mudança de filtro de leitura, não de estado | nenhum novo; a `hint` e a `descricao` já trafegam para o prompt |
| **C3** | `atendimento.iniciado` — autor, contato, fluxo, `ja_existia` | `atendimento.iniciado_manualmente` — autor, contato, fluxo. **Não o texto da mensagem** | telefone é PII; texto da primeira mensagem é conteúdo do cliente. Nem um nem outro em log |
| **C4** | `contato.cadastrado` / `.atualizado` | `contato.criado`, `.atualizado`, `.vinculado_cliente` | telefone, e-mail e documento são PII — auditar **quais campos** mudaram, não os valores |

Política de instrumentação, conforme a arquitetura de erros do projeto:
repositórios de tenant via `run_in_tenant_transaction` + `#[instrument(skip_all)]`;
`#[tracing::instrument(err)]` só onde todo erro é falha real de infraestrutura —
não é o caso aqui, onde "descartei o campo" é resultado normal, não erro.

Trilha de auditoria publicada assíncrona no `transport::bus` → `data_postgres`,
como o resto do sistema.

---

## Notas gerais

- **Não há dado legado.** `criar` e `upsert` de campo personalizado só são
  chamados por testes (doc 33 §4.3): nenhum tenant tem, ou pode ter, um campo.
  Nenhuma decisão deste plano precisa de migração ou janela de compatibilidade.
- **O limiar de confiança de C1 é o mesmo do D1** de `regras-do-bot-e-permissoes`.
  Enquanto o D1 (deploy 2) não entrega o limiar por tenant, C1 usa 0.8 como
  constante — um número por tenant para "quando confio na IA", nunca dois.
- **N9 E13 depende de C1**: sem o write-back, a barra de confiança que a E13
  planeja exibir é para uma origem que nada sabe gravar.
