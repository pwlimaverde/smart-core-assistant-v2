---
type: plan
name: "Visual do cliente Windows — splash, marca e telas"
planSlug: visual-cliente-windows
description: "Levantamento visual do app Smart Core Tenant no Windows: splash sem marca e fora do tema, duas paletas (a do app e a do guia de marca), janela sem tamanho mínimo e sem centralização, e telas com cores e fontes fixas. Plano em cinco fases; a paleta oficial é decisão do dono do produto antes da fase E."
summary: "V0 decide a paleta oficial e o tipo de splash; V1 splash com marca e tema do app; V2 tokens nas telas de maior uso; V3 janela; V4 limpeza do tema morto e do guia de marca; V5 validação em CI e release beta. Nada roda na máquina local: CI e release beta."
status: filled
progress: 0
generated: "2026-10-12"
scaffoldVersion: "2.0.0"
---

# Visual do cliente Windows

## Contexto

Levantamento feito no código em 12/10/2026, sem executar o app (o projeto não roda testes nem builds na máquina local). Achados:

- **Splash de atualização** (`clients/apps/smart-core-tenant/lib/platform/splash_atualizacao.dart`): spinner e texto sobre o tema padrão do Flutter. Sem logo, sem paleta do app, sem fonte do design system. É a primeira tela que o usuário vê.
- **Splash de boot** (`clients/modulos/initial_loading_module/lib/src/presentation/pages/initial_loading_page.dart`): spinner dentro do app, já com a paleta, mas sem marca.
- **Duas paletas:** o app usa `AppTheme` do design system (dourado `#A98F71`, tons stone, fonte Outfit). `clients/apps/smart-core-tenant/lib/theme/smart_core_theme.dart` tem uma paleta azul (`#0066CC`, Segoe UI) sem nenhuma referência no código. `infra/branding/BRANDING_GUIDE.md` e `colors.json` descrevem o azul. A documentação de marca não bate com o app.
- **Janela** (`clients/apps/smart-core-tenant/windows/runner/main.cpp`): 1280×720 fixos, origem (10, 10), sem centralizar, sem tamanho mínimo, posição não lembrada.
- **Cores fixas** fora do design system (contagem de `Colors.*` / `Color(0x…)`): Kanban 20, faturamento 18, painel 13, evolução 12, auditoria 12, `painel_ficha`, `midia_da_bolha`, `mini_barra_da_conversa`.
- **Tamanhos de fonte fixos** (`fontSize:`): `painel_ficha` 20, Kanban 17, `atendimento_card_content` 9.
- **Logos:** `design_system_module/assets/brand/logo_full.png` tem 710×711 (quadrada). `AppLogo` já escala por altura; o login usa 96 px. O instalador usa `infra/branding/assets/installer-splash.png` (360×200, fundo branco).

## Decisões pendentes (dono do produto)

1. **Paleta oficial:** dourada (a do app hoje) ou azul (a do guia). Sem essa resposta, a fase V1 começa com a dourada, que é a que o app já usa, e a fase V4 fica bloqueada até a decisão.
2. **Splash:** estática (logo e barra de progresso) ou com animação leve (fade da marca)? Padrão proposto: estática, sem custo de build.

## Restrições do projeto

- Não rodar `flutter test`, `cargo test` nem builds na máquina local. Só `format` e `analyze`; validação na CI.
- Mudança de cliente Windows só chega aos apps instalados por release beta (`win-v…`), e a atualização automática acontece antes da tela (ver `clients/apps/smart-core-tenant/lib/bootstrap.dart`).
- Não usar `plan.commitPhase` do dotcontext: ele commita na pasta primária, não no worktree (ver memória `dotcontext-mcp-commits-branch-compartilhada`).
- Não exportar agentes do dotcontext (ver memória `dotcontext-export-presets`).

## Fases

### Fase P — Planejamento (concluída nesta sessão)

- Levantamento e este plano.
- Saída: decisões pendentes listadas acima.

### Fase R — Revisão e decisões

- [ ] Receber a paleta oficial e o tipo de splash.
- [ ] Se a paleta for a azul: definir o tema único (remover o dourado) e atualizar o guia.
- [ ] Se a paleta for a dourada: atualizar `BRANDING_GUIDE.md` e `colors.json` para refletir o app.

### Fase E — Execução

**E1. Splash com marca e tema (`clients/apps/smart-core-tenant`)**
- [ ] `splash_atualizacao.dart`: trocar o `MaterialApp` padrão pelo tema do app (`AppTheme.light`), com fundo da marca, `AppLogo(variant: mark)` centralizado, barra de progresso fina e textos de estado ("Verificando atualizações…", "Atualizando para a versão X…").
- [ ] `initial_loading_page.dart`: mesma identidade (logo e progresso), para não haver salto visual entre a splash e o login.
- [ ] Testes de widget atualizados em `test/splash_atualizacao_test.dart`: a splash mostra a marca e some só depois da verificação.

**E2. Cores e fontes nas telas de maior uso (`clients/modulos/operacional_module`)**
- [ ] Kanban (`kanban_page.dart`): trocar `Colors.*` e `Color(0x…)` por `context.colors` e `fontSize` fixos por `textTheme`.
- [ ] Cartão do atendimento (`atendimento_card_content.dart`) e ficha (`painel_ficha.dart`).
- [ ] Barra da conversa (`mini_barra_da_conversa.dart`) e mídia da bolha (`midia_da_bolha.dart`).

**E3. Telas do admin (`clients/modulos/admin_module`)**
- [ ] Faturamento, painel, evolução e auditoria: mesma troca de cores e fontes. Fazer por último, porque é a área menos usada pelo atendimento.

**E4. Janela do Windows (`clients/apps/smart-core-tenant/windows/runner`)**
- [ ] `main.cpp`: centralizar a janela na tela principal, mantendo 1280×720 como padrão.
- [ ] `win32_window.cpp`: tamanho mínimo (por exemplo 960×600) tratado em `WM_GETMINMAXINFO`.
- [ ] Lembrar a posição e o tamanho entre execuções: fica para depois, porque exige gravar em disco; avaliar se vale a pena.

**E5. Limpeza**
- [ ] Remover `lib/theme/smart_core_theme.dart` (sem referências).
- [ ] Atualizar o instalador: revisar `installer-splash.png` para combinar com a splash (fundo da marca em vez de branco). Depende da decisão 1.

### Fase V — Verificação

- [ ] `dart analyze` e `dart format` nos módulos alterados, na máquina local.
- [ ] CI verde: Flutter (testes de widget) e demais jobs.
- [ ] Ensaio de release (`ci/release-windows-*`) com o teste de auto-update ponta a ponta.
- [ ] Revisão visual: prints do app no Windows (feitos pelo dono do produto) comparados com o levantamento.

### Fase C — Conclusão

- [ ] Publicar a release beta seguinte (`win-v…`) e confirmar o feed.
- [ ] Testar a atualização no app instalado: a splash aparece antes da tela e a marca está correta.
- [ ] Registrar no `.context/docs` a paleta oficial escolhida.

## Critérios de aceite

- Nenhuma cor fixa nas telas de atendimento (Kanban, cartão, ficha, conversa).
- A splash mostra a marca com a paleta oficial, antes de qualquer tela.
- A janela abre centralizada e não pode ser reduzida abaixo do tamanho mínimo.
- Um só sistema de tema no app, e a documentação de marca descreve esse sistema.
