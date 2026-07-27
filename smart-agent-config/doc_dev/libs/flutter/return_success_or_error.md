# Return Success or Error (return_success_or_error)

- **Versão em uso:** 3.0.1 (pub.dev)
- **Status de Atualização:** ✅ ATUALIZADA
- **Última Verificação:** 2026-07-27 (fase C1 — migração v2 → v3)
- **Propósito no Projeto:** abstração de Clean Architecture para as operações de
  negócio dos clients Flutter. Toda chamada devolve `Success` ou `Failure` — nunca
  uma exceção atravessando camadas — com o **erro fechado por feature**, o que
  torna o `switch` exaustivo nos dois níveis (sucesso/falha e, dentro da falha,
  cada erro previsto).
- **Documentação Oficial:** [pub.dev/packages/return_success_or_error](https://pub.dev/packages/return_success_or_error)
- **Autor:** mantida pelo próprio time (repositório em `C:/PROJETOS/FLUTTER/PACKAGES/return_success_or_error`).

> **Como usar no dia a dia:** o guia prático — com os exemplos do nosso código,
> as decisões de granularidade de erro e as armadilhas de teste — está em
> [construcao-feature-com-return-success-or-error.md](../../modelagem_frontend/construcao-feature-com-return-success-or-error.md).
> Este arquivo registra apenas a superfície da lib e o histórico da versão.

---

## 1. Superfície da API (3.0.1)

| Tipo | Papel |
|---|---|
| `ReturnSuccessOrError<TValue, TError>` | Resultado selado: `Success(value)` ou `Failure(error)`. Sem `fold`/`getOrNull`/`isSuccess` — só pattern matching. |
| `Datasource<TData, TParams>` | A chamada externa. **Burra**: devolve o dado ou deixa a exceção subir. |
| `Repository<TData, TParams, TError>` / `RepositoryBase` | A fronteira. `mapError(exception, stackTrace, parameters)` traduz exceção técnica em erro de domínio. **Abstrato** — toda exceção precisa de destino. |
| `UsecaseBase<TValue, TParams, TError>` | Regra pura, sem fonte de dados. |
| `UsecaseBaseCallData<TValue, TData, TParams, TError>` | Regra com fonte: fetch → curto-circuito → `process`. |
| `Parameters` / `NoParams` (`noParams`) | Os dados da chamada. **Só dados** — não carregam erro. |
| `AppError` | Base opcional dos erros: `message`, `toString`, igualdade por valor. É `base` — os erros a **estendem**. |
| `ErrorGeneric(String)` | Caso pronto para o inesperado. |
| `Unit` (`unit`) / `Nil` (`nil`) | `void` e `null` como resultado válido. |

Hooks das bases de usecase:

- `process` — getter que aponta para uma função **estática** (não captura `this`).
- `onUnexpected(exception, stackTrace)` — **abstrato**: converte bug do `process`
  num erro previsto da feature. Vale para o caminho direto e o de isolate.
- `runInIsolate` — despacha **só o `process`** para um `Isolate`. O fetch nunca vai.
- `monitorExecutionTime` + `onExecutionTimeMeasured(Duration)` — medição opcional,
  sobrescrevível para plugar métrica.

---

## 2. Como o projeto usa

- **Uma cadeia por operação:** `Datasource → Repository → Usecase`, montada na DI
  do módulo (`globalBinds`). São 39 operações nos quatro módulos de feature.
- **Erro `sealed` por feature** em `domain/errors/`; os marcadores transversais
  (`NetworkFailure`, `UnauthorizedFailure`, `ValidationFailure`,
  `UnexpectedFailure`) vivem no `domain_models` e permitem à apresentação reagir
  sem conhecer cada caso concreto.
- **Classificação de falha gRPC centralizada** no `api_client`
  (`classificarFalhaGrpc` → `GrpcFailureKind`): a tabela de status codes existe
  uma vez, e cada `mapError` decide o que aquela natureza significa na feature.
- **`runInIsolate` desligado** em todas as operações: os `process` são passthrough
  ou transformações triviais. Ligar exige medição, não palpite.
- **Streams ficam fora da lib** (ela é request/response): o realtime do
  atendimento usa um port de domínio próprio, e a política de reconexão vive na
  apresentação.

---

## 3. Migração v2 → v3 (o que quebrou)

1. `ReturnSuccessOrError<T>` → `ReturnSuccessOrError<TValue, TError>`.
2. `SuccessReturn(success: v)`/`.result` → `Success(v)`/`.value`;
   `ErrorReturn(error: e)`/`.result` → `Failure(e)`/`.error`.
3. Nova camada `Repository` **obrigatória** entre datasource e usecase; o usecase
   recebe `{required super.repository}`.
4. `Datasource` não lança mais `parameters.error` — deixa a exceção técnica subir.
5. `ParametersReturnResult` (com `AppError get error`) → `Parameters` (só dados);
   `NoParams` perdeu o parâmetro `error` e ganhou o singleton `noParams`.
6. `AppError` virou `abstract base class`: `implements AppError` não compila mais,
   e `copyWith` saiu do contrato.
7. `onUnexpected` passou a ser **abstrato** nas bases de usecase.
8. Os códigos `Cod. 02-1` e `Cod. IsolateCatch` (enriquecimento automático de
   mensagem) não existem mais.
9. `process` recebe os parâmetros **tipados** — sem `parameters as MeusParametros`.

O impacto disso no nosso código está registrado no plano da fase C1
(`doc_dev/planejamento/25-fase-C1-clients-rsoe-v3.md`).
