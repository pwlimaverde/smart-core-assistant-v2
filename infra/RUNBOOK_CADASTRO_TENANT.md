# Cadastro de tenant pela aplicação — como colocar em uso

Quem lê isto quer uma de duas coisas: **testar o fluxo em dev** ou **entender o
que muda quando o gateway de pagamento entrar**. As duas estão aqui.

## O desenho em uma frase

O tenant nasce **inativo** no passo 1 e só é ligado quando um **provedor de
pagamento** confirma. Hoje o único provedor é o **voucher**, que confirma na
hora; um gateway real entra como outro provedor da mesma porta, sem mexer no
wizard nem na máquina de estados da assinatura.

```
/cadastro            → cria auth_user + tenant(inativo) + subscription(PENDING_PAYMENT)
/cadastro/plano      → grava plan_id
/cadastro/pagamento  → voucher confirma na hora │ gateway devolve URL e confirma depois
/cadastro/pronto     → tenant.active = true, assinatura ACTIVE, login automático
```

## Antes do primeiro teste

### 1. Aplicar a migration e publicar juntos

A `0027_vouchers_planos.sql` cria as tabelas de voucher e semeia o plano
**Básico** (3 instâncias de WhatsApp, 3 departamentos, 5 fluxos).

> **Ordem importa.** Rodar a migration no banco de dev **antes** de o código
> novo estar publicado derruba os serviços que ainda não conhecem o arquivo
> (`migration 27 was previously applied but is missing`). Aplique pelo deploy,
> ou aplique e publique na sequência — não deixe a janela aberta.

### 2. Criar o voucher de teste

Pelo painel do superusuário: **Faturamento → Vouchers → Novo voucher**.

| Campo | Valor para os testes |
|---|---|
| Código | `devteste` |
| Plano | Básico |
| Duração concedida | `180` dias (≈ 6 meses) |
| Máximo de resgates | `0` (ilimitado — dá para cadastrar várias contas de teste) |

O código não distingue maiúsculas de minúsculas: `devteste`, `DevTeste` e
`DEVTESTE` são o mesmo voucher, e o banco impede que duas grafias coexistam.

Não há script de seed de propósito: dado de teste em migration vaza para
produção, e criar pelo painel exercita a tela nova.

### 3. Ligar o enforce de quota (opcional, mas é o ponto do teste)

O limite de 3 instâncias só **bloqueia** com a variável ligada; o padrão é
log-only. No `/opt/smartcore/dev/env/dev.env`:

```
SMARTCORE_QUOTA_ENFORCE=true
```

Sem isso, o tenant do plano Básico consegue criar a 4ª instância e o limite
aparece só no log. Ver `RUNBOOK_ENFORCE_ROLLOUT_N8.md` para o rollout em
produção.

## O roteiro de teste

1. Abrir `/cadastro` no app (desktop ou web), preencher empresa, e-mail e senha.
   O endereço da conta é sugerido a partir do nome e checado enquanto se digita.
2. Escolher o plano Básico.
3. Informar `devteste` no campo de código.
4. A conta é liberada e o login acontece sozinho.

**Confirmar no banco** que a assinatura ficou como esperado:

```sql
SELECT t.slug, t.active, s.status, s.current_period_end, p.name
  FROM tenants_tenant t
  JOIN tenants_subscription s ON s.tenant_id = t.id
  JOIN tenants_plan p ON p.id = s.plan_id
 WHERE t.slug = '<o slug que você usou>';
```

Esperado: `active = true`, `status = ACTIVE`, `current_period_end` seis meses à
frente.

**Testar a revogação:** revogue o `devteste` no painel e tente cadastrar de novo
— o código deve ser recusado. A conta criada antes continua funcionando: revogar
um código não rescinde contrato firmado. Para encerrar uma conta específica, use
`SetTenantActive` na tela de tenants.

## Quando o gateway de pagamento entrar

Três passos, nenhum deles no cliente:

1. Implementar `ProvedorPagamento` (`server/crates/application/src/pagamento/`)
   para o gateway escolhido. `iniciar` devolve `IntencaoPagamento::Redirect` com
   a URL da cobrança.
2. Registrar o provedor na `RegistroProvedores` (`grpc_web.rs`, função `serve`).
3. Expor um webhook que chame `ActivateSignup` quando a confirmação chegar. O
   handler já é **idempotente**: um webhook repetido não estende o período.

A tela de pagamento já trata o caminho assíncrono — abre a URL no navegador do
sistema e acompanha por `GetSignupStatus` até o tenant ficar ativo.

## Limitações conhecidas

- **Não há verificação de e-mail.** O v2 não tem serviço de SMTP; qualquer
  e-mail é aceito. Antes de produção: ou entra um provedor de e-mail, ou o
  `access_code` de `tenants_tenant` vira o portão (o superusuário gera e entrega
  ao cliente, e o wizard passa a exigi-lo).
- **O limite de fluxos é medido, não aplicado.** Não existe RPC de criação de
  fluxo para chamar o enforce — `FluxoAtendimentoRepository::criar` não é
  exposto. O `max_fluxos` do plano existe e é contabilizado; morde quando o CRUD
  de fluxos existir.
- **Cadastros abandonados** ficam como tenants inativos com assinatura
  `PENDING_PAYMENT`. Um job de limpeza ainda não foi escrito.
- **O código do voucher é guardado em claro.** É código de campanha — o
  superusuário precisa relê-lo no painel para distribuir — e no pior caso
  concede uma assinatura, não acesso a dados. A defesa é rate limit por IP,
  auditoria de cada tentativa recusada e revogação. Para códigos únicos por
  cliente (um por e-mail), o certo seria hash e exibição única na geração.
