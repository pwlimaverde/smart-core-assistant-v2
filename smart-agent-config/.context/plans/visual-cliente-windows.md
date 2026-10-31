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

- [x] Receber a paleta oficial e o tipo de splash. Paleta oficial: dourada/stone (`workspace-tokens.css` do designer). Splash: estática, com a logo.
- [x] (N/A) a paleta é a dourada.
- [x] `BRANDING_GUIDE.md` e `colors.json` atualizados (commit `e4f6006e`).

### Fase E — Execução

**E1. Splash com marca e tema (`clients/apps/smart-core-tenant`)**
- [x] `splash_atualizacao.dart`: trocar o `MaterialApp` padrão pelo tema do app (`AppTheme.light`), com fundo da marca, `AppLogo(variant: mark)` centralizado, barra de progresso fina e textos de estado ("Verificando atualizações…", "Atualizando para a versão X…").
- [x] `initial_loading_page.dart`: mesma identidade (logo e progresso), para não haver salto visual entre a splash e o login.
- [x] Testes de widget atualizados em `test/splash_atualizacao_test.dart`: a splash mostra a marca e some só depois da verificação.

**E2. Cores e fontes nas telas de maior uso (`clients/modulos/operacional_module`)**
- [~] Kanban (`kanban_page.dart`): cores trocadas por `context.colors` (`e4f6006e`). Tamanhos de fonte: **não trocados por `textTheme`**; ver "Revisão de 29/10".
- [~] Cartão do atendimento (`atendimento_card_content.dart`) e ficha (`painel_ficha.dart`): cores trocadas no cartão; `painel_ficha.dart` ainda tem 3 cores fixas e as fontes da revisão.
- [~] Barra da conversa (`mini_barra_da_conversa.dart`, 6 cores fixas) e mídia da bolha (`midia_da_bolha.dart`, 3 cores fixas) pendentes.

**E3. Telas do admin (`clients/modulos/admin_module`)**
- [ ] Faturamento, painel, evolução e auditoria: mesma troca de cores e fontes. Fazer por último, porque é a área menos usada pelo atendimento.

**E4. Janela do Windows (`clients/apps/smart-core-tenant/windows/runner`)**
- [x] `main.cpp`: centralizar a janela na tela principal, mantendo 1280×720 como padrão.
- [x] `win32_window.cpp`: tamanho mínimo (por exemplo 960×600) tratado em `WM_GETMINMAXINFO`.
- [ ] Lembrar a posição e o tamanho entre execuções: fica para depois, porque exige gravar em disco; avaliar se vale a pena.

**E5. Limpeza**
- [x] Remover `lib/theme/smart_core_theme.dart` (sem referências; confirmado em 29/10).
- [ ] Atualizar o instalador: revisar `installer-splash.png` para combinar com a splash (fundo da marca em vez de branco). Depende da decisão 1.

### Fase V — Verificação

- [x] `dart analyze` e `dart format` nos módulos alterados, na máquina local.
- [x] CI verde: Flutter (testes de widget) e demais jobs (`25f3dbe7`, `9cf91124`).
- [x] Ensaio de release (`ci/release-windows-sobre`) com o teste de auto-update ponta a ponta.
- [x] Revisão visual pelo dono do produto, no app instalado (beta.9 validada). Prints: não anexados. (feitos pelo dono do produto) comparados com o levantamento.

### Fase C — Conclusão

- [x] Publicar a release beta seguinte (beta.8 e beta.9). (`win-v…`) e confirmar o feed.
- [x] Testar a atualização no app instalado (validado pelo dono do produto).: a splash aparece antes da tela e a marca está correta.
- [ ] Registrar no `.context/docs` a paleta oficial escolhida. Pendente.

## Critérios de aceite

- Nenhuma cor fixa nas telas de atendimento (Kanban, cartão, ficha, conversa).
- A splash mostra a marca com a paleta oficial, antes de qualquer tela.
- A janela abre centralizada e não pode ser reduzida abaixo do tamanho mínimo.
- Um só sistema de tema no app, e a documentação de marca descreve esse sistema.

## Revisão de 29/10/2026

- **Tamanhos de fonte fixos (58 ocorrências em `operacional_module`, mais 1–3 por tela em `tenant_module`): premissa revista.** O item pedia trocar por `textTheme`. Verificado no código: o Flutter aplica o fator de escala de texto do sistema também a `fontSize` fixo, então a acessibilidade não depende de estilo do tema. Trocar por `textTheme` mudaria tamanhos (`AppTypography` tem 11, 13, 14, 18, 24 e 32; a interface usa 10, 11.5, 12, 12.5, 16 e 22) e quebraria layouts densos sem ganho visual. **Decisão: manter os tamanhos.** Se a intenção era escala única, o caminho é ajustar `AppTypography` e migrar tela a tela com conferência visual.
- **Cores fixas restantes:** `mini_barra_da_conversa.dart` (6), `painel_ficha.dart` (3), `midia_da_bolha.dart` (3), `dialogo_etapa.dart` (3), `galeria_do_atendimento.dart` (2), `atendimento_card_content.dart` (2), `avatar_do_contato.dart` (1), `pareamento_dialog.dart` (1), `tenant_drawer.dart` (1). Pendente.
- **Janela:** lembrar a posição entre execuções fica fora desta fase (exige gravar em disco; a centralização e o tamanho mínimo já estão no ar).
- **Instalador:** `installer-splash.png` ainda tem fundo branco. Pendente.
- **Paleta no `.context/docs`:** pendente.

## Decisão sobre as cores fixas restantes (29/10/2026, revisão)

As 24 ocorrências de `Colors.white`, `Colors.black87`, `Colors.transparent` e `Color.lerp` nas telas de atendimento ficam como estão. São overlays sobre mídia, foto ou barra escura (galeria, barra da conversa, miniatura da mídia, avatar), e o texto e o ícone precisam ser brancos para ter contraste sobre a imagem; o tema claro/escuro não muda o fundo delas. A cor de etiqueta vem de dado do usuário e é escurecida em código de propósito. Trocar por tokens quebraria o contraste sem ganho visual. Item encerrado.
