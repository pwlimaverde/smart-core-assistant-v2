# Plano completo — Cadastro retomável e pagamento resolvível pelo dono

> Verdade técnica da correção. Levantado direto do código e do banco do dev em
> 2026-09-06, com o defeito reproduzido no tenant `Paulo Ecoprint`
> (`866387ab-e159-467f-bf19-1fb70058ff14`).

## Estado observado (evidência)

```
tenants_tenant        | active = f | onboarding_step = 8
tenants_subscription  | status = PENDING_PAYMENT | plan_id = 1 | period_end = NULL
runtime_api  (13:48–13:55) | AUTH_INVALID_TOKEN x5   ← a sessão expirando no wizard
data_postgres(13:58, 14:00)| "assinatura inadimplente" ← cada tentativa de cadastrar
```

O `onboarding_step = 8` mapeia para `/configuracao/pronto`
(`rota_publica.dart`), e é para lá que o guard mandou — apesar de a assinatura
nunca ter sido paga.

## O que já existe (não refazer)

- `tenants_voucher` com resgate **idempotente e concorrente-seguro**:
  `UPDATE ... WHERE (max_resgates = 0 OR resgates_usados < max_resgates)
  RETURNING` (`vouchers.rs:159`). `max_resgates = 0` significa **ilimitado**.
- Normalização de código (`devteste` = `DEVTESTE` = `" devteste "`).
- `ConfirmPayment` com o registro de provedores (`voucher` hoje; gateway externo
  previsto por `ModoConfirmacao`).
- Guarda de inadimplência no `data_postgres`, que já barra escrita de tenant sem
  assinatura ativa.
- `PortaoConfiguracao`: consulta única por sessão, tri-estado (`null` = não sei),
  e falha resolvendo para "não pendente". O padrão a seguir na E3.

## E1 — O progresso passa a falar de dinheiro

### Contrato

`GetMyOnboardingProgressResponse` (admin.proto) ganha campos **aditivos**:

```proto
message GetMyOnboardingProgressResponse {
  int32 passo = 1;
  bool concluido = 2;
  // Novos — o cliente não tinha como saber que a conta está pendente.
  bool pagamento_pendente = 3;   // subscription.status != ACTIVE
  string assinatura_status = 4;  // PENDING_PAYMENT | ACTIVE | SUSPENDED | ...
  string plano_nome = 5;         // para a tela dizer o que está sendo cobrado
}
```

Aditivo de propósito: campo novo em proto3 não quebra cliente antigo, e o app
em campo continua funcionando enquanto não atualiza.

**Onde:** `handler_get_my_onboarding_progress` no `data_postgres` passa a ler
`tenants_subscription` no mesmo `SELECT` (JOIN com `tenants_plan`), e o
`runtime_api` repassa. Uma consulta a mais, no caminho que já roda uma vez por
sessão.

### Testes
Tenant sem assinatura, com `PENDING_PAYMENT` e com `ACTIVE` → os três estados
chegam corretos ao cliente.

## E2 — Quitar sem `signup_token`

### Contrato

RPC **autenticado** novo no `AdminService` (não no `OnboardingService`, que é
público):

```proto
rpc QuitarMinhaAssinatura(QuitarMinhaAssinaturaRequest) returns (QuitarMinhaAssinaturaResponse);

message QuitarMinhaAssinaturaRequest {
  string provedor = 1;    // "voucher"
  string credencial = 2;  // o código digitado
}
message QuitarMinhaAssinaturaResponse {
  bool confirmado = 1;
  string assinatura_status = 2;
  string url_externa = 3;  // quando o provedor exigir concluir fora do app
  string erro_legivel = 4; // "voucher expirado", "já utilizado", …
}
```

O `tenant_id` sai das **claims**, nunca do request — mesma regra dos demais
`*My*`. Reusa o registro de provedores e o resgate do `ConfirmPayment`; a
diferença é só a origem da identidade (sessão × `signup_token`).

### Autorização
Exige `tenant:admin` (ou `*`). Um colaborador não vê cobrança do tenant. O
`data_postgres` valida de novo, sem confiar na tela.

### Auditoria
`assinatura.quitada`: autor, meio (`voucher`), plano e período resultante.
**Nunca** o código do voucher — é credencial reutilizável enquanto tiver
resgates.

### Idempotência
Dois cliques não podem consumir dois resgates. O `UPDATE ... RETURNING` já
resolve a corrida entre requisições; falta a guarda de "assinatura já ativa":
quitar uma assinatura `ACTIVE` responde `confirmado = true` **sem** tocar no
voucher.

### Testes
Voucher válido ativa; expirado, revogado e esgotado devolvem motivo legível;
assinatura já ativa não consome resgate; colaborador sem escopo recebe
`PermissionDenied`.

## E3 — O guard passa a olhar a assinatura

`tenantAuthRedirectTarget` ganha `pagamentoPendente` (tri-estado, igual ao
`onboardingPendente`) e a regra:

```
pagamento pendente  →  /conta/pagamento     (precede o roteiro)
roteiro pendente    →  rotaDeConfiguracaoDoPasso(passo)
caso contrário      →  /atendimentos
```

Ordem importa: hoje o roteiro vence e leva a `/configuracao/pronto`, que é
exatamente a tela que mente para quem não pagou.

**Falha de consulta resolve para "não pendente"** — mesma escolha já feita e
justificada no `PortaoConfiguracao`. Prender quem já pagou por causa de uma
consulta que falhou é pior do que deixar entrar.

O `PortaoConfiguracao` passa a expor `pagamentoPendente` junto do que já expõe:
os dois vêm da mesma consulta, então não há chamada extra.

### Testes (guard é função pura, testável na VM)
- pendente + roteiro pendente → vai para pagamento (o pagamento vence);
- pendente + já em `/conta/pagamento` → não redireciona (evita laço);
- não pendente → comportamento atual intacto;
- `null` (não sei) → segura na splash, como hoje.

## E4 — Tela de pagamento depois do login

Rota `/conta/pagamento` no `tenant_module` (é assunto de conta, não de
atendimento), com:

- o que está pendente: plano, valor e desde quando;
- campo de voucher, com o erro do servidor exibido junto do campo — não em
  snackbar que some;
- quando o provedor pedir pagamento externo, o botão que abre a URL;
- ao confirmar, o `PortaoConfiguracao` é atualizado sem nova consulta (como o
  `concluir()` já faz) e a navegação segue para o roteiro ou para o quadro.

**Visível só para o dono.** Sem `tenant:admin`, a rota não é registrada no menu
e o guard devolve ao quadro — o mesmo padrão já usado para `/tenant/*`.

## E5 — Aviso enquanto estiver pendente

Faixa no topo do quadro (reusa o slot `avisoBuilder` criado para o
`AvisoConexao`), com dois textos:

- **dono:** "Assinatura pendente. Nada será recebido nem enviado até
  regularizar." + botão para `/conta/pagamento`;
- **colaborador:** mesma primeira frase, sem botão — "fale com o responsável
  pela conta".

Sem isso, o sintoma continua sendo "não consigo cadastrar nada" com uma
mensagem de erro de banco.

## Sequência

E1 → E2 (servidor, um deploy) → E3 → E4 → E5 (cliente). E3 sem E1 não tem o que
consultar; E4 sem E2 não tem o que chamar.

## Riscos

- **Operação financeira exposta a mais gente do que devia.** Mitigar com escopo
  no RPC + revalidação no `data_postgres` + auditoria.
- **Laço de redirecionamento** se a tela de pagamento não for exceção na regra
  do guard. Coberto por teste.
- **Cliente antigo em campo** não conhece `/conta/pagamento`. Como os campos são
  aditivos, ele continua no comportamento de hoje — degradado, não quebrado.
- **Voucher em log.** É credencial: `skip_all` no span e ausência na auditoria.

## Fora de escopo

- Gateway de pagamento real (Stripe/Asaas). `ModoConfirmacao` e `url_externa`
  ficam prontos para recebê-lo, sem implementar.
- Cobrança recorrente e renovação automática.
- Tela de histórico de pagamentos (`tenants_paymentrecord` já existe e está
  vazia).
