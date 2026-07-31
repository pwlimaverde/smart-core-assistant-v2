# Cadastro de tenant pela aplicação — como colocar em uso

Quem lê isto quer uma de duas coisas: **testar o fluxo em dev** ou **entender o
que muda quando o gateway de pagamento entrar**. As duas estão aqui.

## O desenho em uma frase

O tenant nasce **inativo** no passo 1 e só é ligado quando um **provedor de
pagamento** confirma. Hoje o único provedor é o **voucher**, que confirma na
hora; um gateway real entra como outro provedor da mesma porta, sem mexer no
wizard nem na máquina de estados da assinatura.

O alvo é o **app instalado no Windows**. A versão web do app do tenant existe,
mas não é o caminho desta fase — e num programa instalado não há URL para
digitar, então a tela de login oferece "Criar conta da minha empresa". Sem esse
botão o cadastro seria inalcançável.

### Trilha 1 — criar a conta (pública, sem sessão)

```
/cadastro            → cria auth_user + tenant(inativo) + subscription(PENDING_PAYMENT)
/cadastro/plano      → grava plan_id
/cadastro/pagamento  → voucher confirma na hora │ gateway devolve URL e confirma depois
/cadastro/pronto     → tenant.active = true, assinatura ACTIVE, login automático
```

### Trilha 2 — colocar para operar (com sessão)

Pagar cria a conta; quem coloca o sistema para funcionar é este roteiro. Emenda
direto no fim da trilha 1.

```
/configuracao/whatsapp      → cria a instância e mostra o QR do Evolution
/configuracao/departamento  → primeiro setor de atendimento
/configuracao/assistente    → persona e nome do bot
/configuracao/pronto        → marca setup_completed e vai para o workspace
```

**Todo passo pode ser adiado.** Parear o WhatsApp exige o celular em mãos, e
quem instala o programa nem sempre é quem tem o telefone — bloquear ali deixaria
o cliente preso. "Fazer isso depois" registra o progresso do mesmo jeito.

**O progresso vive no servidor** (`tenants_tenant.onboarding_step`), não no app:
fechar o programa e reabrir continua de onde parou, que num app instalado é o
esperado.

**`setup_completed` mudou de significado.** Antes era marcado quando o pagamento
confirmava; agora é marcado no fim da trilha 2. Passou de "pagou" para "está
operando".

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

### 3. Enforce de quota — já ligado em dev

`SMARTCORE_QUOTA_ENFORCE=true` está no `/opt/smartcore/dev/env/dev.env` (backup
do arquivo anterior ao lado, com data no nome).

**O valor do limite nunca esteve no código.** `verificar_quota` faz
`SELECT p.max_instances FROM tenants_subscription s JOIN tenants_plan p ...` —
o teto é sempre o do plano do tenant. Esta variável só decide se exceder
**recusa** ou apenas **registra no log**. Mudar o Básico de 3 para 5 instâncias
no painel passa a valer na hora, sem deploy.

Quem lê a variável: `data_postgres`, `data_storage`, `data_whatsapp` e
`webhook_ingress`. Ela é injetada pelo `env_file` do compose, que o deploy copia
do `dev.env` — mudar o arquivo exige **recriar** os contêineres (`docker compose
up -d --force-recreate`), não apenas reiniciar: o ambiente é lido na criação.

Para o rollout em produção, ver `RUNBOOK_ENFORCE_ROLLOUT_N8.md` — lá a
recomendação é observar em modo aviso antes de bloquear.

## O roteiro de teste

1. Abrir o app e clicar em **"Criar conta da minha empresa"** na tela de login.
   Preencher empresa, e-mail e senha — o endereço da conta é sugerido a partir
   do nome e checado no servidor enquanto se digita.
2. Escolher o plano Básico.
3. Informar `devteste` no campo de código.
4. A conta é liberada, o login acontece sozinho e o roteiro segue para a
   configuração: WhatsApp (QR), setor, assistente e conclusão.

**Confirmar no banco** que a assinatura ficou como esperado:

```sql
SELECT t.slug, t.active, s.status, s.current_period_end, p.name
  FROM tenants_tenant t
  JOIN tenants_subscription s ON s.tenant_id = t.id
  JOIN tenants_plan p ON p.id = s.plan_id
 WHERE t.slug = '<o slug que você usou>';
```

Esperado: `active = true`, `status = ACTIVE`, `current_period_end` seis meses à
frente. E `setup_completed` **false** até o tenant terminar a trilha 2 —
`onboarding_step` mostra em qual tela ele parou (5 = WhatsApp, 8 = concluído).

**Testar o limite do plano:** com o Básico (3 instâncias), crie três conexões e
tente a quarta. O `data_whatsapp` recusa antes de falar com o Evolution, e a
tela diz que o limite do plano foi atingido — não "servidor indisponível".

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
