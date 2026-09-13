# 36 — Cronograma: pendências dos planos, de ponta a ponta

> Nasce do levantamento de 12/09 (doc 35, "Levantamento de pendências dos
> planos"). Execução em ordem, um bloco por vez. Este arquivo é a fonte de
> verdade do andamento: cada bloco só vira ✅ com o CI verde no `dev`.

## Regras de execução

1. **Confirmar antes de construir.** O levantamento foi por marcadores no
   código; cada bloco começa conferindo o que já existe, para não refazer.
2. **Ponta a ponta:** contrato → banco/sqlx → `data_postgres` → `runtime_api`
   (método concreto no `grpc_web.rs` + `rbac::MAPA`) → stubs → Flutter (RSOE) →
   testes → doc.
3. **Testes rodam no CI**, não nesta máquina. CI vermelho = corrigir e reenviar
   antes de abrir o bloco seguinte.
4. **Um commit por bloco** no `dev`, e este cronograma atualizado no mesmo
   commit.

## Blocos

| # | Bloco | Origem | Por que nesta posição | Estado |
|---|-------|--------|-----------------------|--------|
| B1 | Recuperação de senha e reenvio de convite | N11 E8 | Convidado ou usuário que perde o e-mail/senha hoje não tem saída | ⏳ em andamento |
| B2 | Menu por escopo, não por `isTenantAdmin` | doc 35-agentes F2 | O papel somente-leitura (D4) existe no servidor e não na tela; pré-requisito do B3 | ⬜ |
| B3 | "O que o agente fez" — auditoria do próprio tenant | doc 35-agentes F1 | Fecha o DoD da N13: agente só é aceitável se auditável por quem o autorizou | ⬜ |
| B4 | Limiar de confiança com veto, por tenant | regras D1 | Hoje o C1 usa 0,8 fixo; um número por tenant para "quando confio na IA" | ⬜ |
| B5 | Notificar o atendente da atribuição | regras D6 | Rodízio (D2) atribui em silêncio | ⬜ |
| B6 | Marcar como lida e contador de não lidas | N9 E4 | Sem isso o quadro não diz o que falta responder | ⬜ |
| B7 | Ajustar permissões de um agente sem desconectar | doc 35-agentes F4 | Hoje a única saída é revogar e reconectar | ⬜ |
| B8 | Descoberta dos aplicativos conectados | doc 35-agentes F5 | Recurso que precisa ser explicado por fora não foi entregue | ⬜ |
| B9 | IA analítica: assunto automático, feedback do teste, treinamento por arquivo | N10 E2, E6, E5 | Maior e mais caro; depende de nada acima | ⬜ |
| B10 | Clientes PJ e vínculo contato ↔ cliente | N11 E5 / doc 34 C4 | Entidade nova com tela própria | ⬜ |

**Fora deste cronograma:** N12 (cutover de produção) — é operação com janela
combinada, dump de produção e go/no-go; não é código a executar sozinho.

## Andamento

<!-- Cada bloco concluído ganha aqui: commit, run de CI e o que ficou de fora. -->

### B1 — Recuperação de senha e reenvio de convite

**Confirmado antes de construir:** o e-mail transacional (N11 E7) já existia
(`infrastructure_email`, SMTP/Brevo, usado pelo convite); recuperação de senha e
reenvio de convite não existiam em lugar nenhum.

**Entregue:**

- **Pedir o link** (`AuthService.SolicitarRedefinicaoSenha`, pública): responde
  "aceito" exista a conta ou não, e o e-mail sai em segundo plano para o tempo
  de resposta também não contar. Rate limit por IP (dito ao cliente) e por
  conta (silencioso). O token nasce na borda; o banco recebe só o SHA-256
  (`auth_password_reset`, migration 0033). Um pedido novo aposenta os
  anteriores. Validade de 1 hora. Conta desativada não recebe link.
- **Trocar a senha** (`AuthService.RedefinirSenha`, pública): consome o token e
  grava o hash argon2 numa transação só — dois cliques não gastam o link duas
  vezes. Link que não vale é `failedPrecondition` e senha fraca é
  `invalidArgument`, para a tela dizer "peça outro link" num caso e "escolha
  outra senha" no outro. Depois de trocar, **todas as sessões do usuário
  caem**: o Redis ganhou o índice de famílias de refresh por usuário
  (`auth:refresh_user:<id>`) e a rota `RevokeUserSessions`.
- **Reenviar convite** (`AdminService.ReenviarConvite`, `tenant:admin`): renova a
  validade e manda o mesmo link. Vencido pode; aceito ou revogado, não. Três
  reenvios por hora por convite.
- **Telas:** `/recuperar-senha` e `/redefinir-senha` no `login_module` (os dois
  apps), "Esqueci minha senha" no login, públicas nos dois guards; o link do
  e-mail sobrevive ao boot pelo `?retomar=` da rodada anterior. Botão
  "Reenviar" na tela de convites.
- **Auditoria:** `password_reset_requested`, `password_reset_completed`,
  `tenant_invite_resent`. Nem token, nem senha, nem e-mail em log.

**Fica de fora:** sessões abertas antes deste deploy não estão no índice por
usuário — expiram sozinhas no TTL do refresh. O access token já emitido segue
válido até expirar (minutos), como no logout.

### B2 — Menu por escopo, não por `isTenantAdmin`

**Confirmado antes de construir:** `tenant_drawer.dart` ainda envolvia nove itens
num `if (isTenantAdmin)`, e o guard devolvia qualquer `/tenant/*` ao quadro sem
`tenant:admin`. Cruzar tela a tela com as chamadas de abertura achou **duas
divergências no próprio servidor**, que entraram no bloco:

- **Fluxos:** a borda exigia `kanban:admin` para escrever em fluxo e coluna, e o
  banco exigia `operacional:admin`. Um `manager` com `kanban:admin` passava na
  borda e era recusado no banco — exatamente o caso que a N13.3 quis liberar.
  O banco passou a aceitar `kanban:admin` também.
- **Contatos:** a borda exigia `clientes:read` para listar, e o banco já aceitava
  `atendimentos:read`. Um `staff` convidado com os escopos padrão
  (`atendimentos:*`, `clientes:write`) não achava ninguém no "iniciar
  atendimento". A borda passou a aceitar `atendimentos:read`.

**Entregue:**

- `tenant_module/lib/permissoes_de_tela.dart`: o mapa tela → escopos para abrir
  e para alterar, espelho do `rbac::MAPA`, sem import nenhum (o guard o importa
  e continua testável na VM). Lista vazia é só admin; `/tenant/*` não declarado
  é só admin (fail-closed, como no servidor); subtela herda a seção.
- Menu montado pelo mapa; guard do app usando o mesmo mapa — nada visível leva a
  redirect, nada escondido abre pela URL.
- Botões de escrita escondidos sem o escopo de escrita em contatos, equipe,
  fluxos, colunas, campos, conexões, configuração e treinamento (material e
  intenções). O interruptor da IA por conexão fica visível e só o admin muda.
  O treinamento, que mora noutro módulo e não conhece a sessão, recebe a
  pergunta pronta do app.
- Testes: um por papel no menu (manager, staff, viewer, sem sessão), regras do
  mapa, guard por escopo, e `permissoes_de_tela_test.dart`, que **lê o
  `rbac.rs`** e falha se a tela e o servidor divergirem.

**Fica de fora:** o quadro de atendimento (`operacional_module`) continua
oferecendo enviar/mover para um `viewer` — o servidor recusa (N13.3), mas a tela
não esconde. É do quadro, não do menu, e fica anotado para quando o quadro for
revisto.
