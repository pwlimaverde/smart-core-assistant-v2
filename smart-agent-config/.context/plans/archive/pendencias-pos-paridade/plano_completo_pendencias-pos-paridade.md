# Pendências pós-paridade — plano completo

> Criado em 2026-09-19, depois do fechamento da paridade v1 (P1–P12, doc 37,
> CI verde no run 35460056817).
> Docs das libs e do provedor: `info_aux_pendencias-pos-paridade.md`.
> Branch de trabalho: `feat/pendencias-pos-paridade`, aberta a partir da
> `feat/paridade-v1`.

## Origem

Varredura de 19/09: planos N9–N13, regras do bot, painel CRM, as seções "fica
de fora" do doc 36 e o doc 37, cruzados com o código de hoje. Os marcadores
`status: pending` dos planos em `.context/plans/` **não** foram tomados como
verdade. Cada item abaixo foi conferido no código.

| # | Pendência | Origem | Evidência no código |
|---|---|---|---|
| 1 | Foto e nome do contato na tela | N11 E6 | `GetWhatsappProfilePicture` existe só no `data_whatsapp`; nenhum RPC nem tela usa. A foto do `CONTACTS` (P8) é gravada e não aparece. |
| 2 | Etiquetagem por intenção | N10 E3 | `atu_etiqueta_atendimento` sem coluna `origem`; nenhum código aplica etiqueta por intenção |
| 3 | Enriquecer o contato pelas entidades | N10 E4 | `entidades_extraidas` é gravada na mensagem (B9) e nada a leva ao contato |
| 4 | Quadro esconde ações de quem só lê | doc 36 B2 | o servidor recusa, a tela oferece |
| 5 | Marca "revisar" no cartão | doc 36 B4 | a decisão `revisao` só existe no evento `bot.respondeu` |
| 6 | Aviso de atribuição fora do quadro | doc 36 B5 | só SnackBar com o quadro aberto |
| 7 | Revisão das avaliações do teste | doc 36 B9 (opcional no plano) | `treinamento_query_test_feedback` sem tela de leitura |
| 8 | Fechar o fallback de escopos | regras D4, passos 2 e 3 | só o passo 1 (medição `origem_escopos`) |

**Fora deste plano:**
- **N12, cutover de produção:** operação com janela, dump e go/no-go.
- **Teste de resposta com mídia** (N10 E6.1): opcional no plano original e sem
  pedido de uso. Fica registrado como decisão de não fazer agora.

## Regras de execução

As mesmas do doc 36 e do doc 37, que funcionaram:

1. **Confirmar antes de construir.** Cada fase abre conferindo o que já existe.
2. **Ponta a ponta:** contrato → migration → `infrastructure_postgres` →
   `data_postgres` (porta, adapter **dentro do `impl`**, rota) → `runtime_api`
   (método concreto em `grpc_web.rs`; `encaminhar_operacional` quando houver
   RBAC por fluxo; entrada no `rbac::MAPA` quando passar por
   `encaminhar_tenant`) → stubs Dart → Flutter RSOE → testes → doc.
3. **Testes só na CI.** Vermelho = corrigir e reenviar antes da fase seguinte.
4. **`cargo fmt --all` antes de todo push.** Consulta nova sem macro.
5. **Tela nova entra com teste de widget** (piso de cobertura 78%).
6. Commits sem `Co-Authored-By` e sem "Generated with"; comentários em pt-BR.

## Ordem e dependências

```
P13 foto do contato ─────────── independente, corrige defeito latente primeiro
P14 etiquetas por intenção ──┐
P15 enriquecimento do contato┘ mesma transação do AnexarAnaliseMensagem (B9)
P16 acabamentos do quadro ──── independente; (c) usa lib nova
P17 revisão das avaliações ─── independente
P18 fallback de escopos ────── GATE: medição de produção antes do passo 3
```

P14 antes de P15: as duas estendem o mesmo handler, e P14 é a que tem regra
de conflito com humano (a mais arriscada). Fazê-la primeiro fixa o padrão.

---

## P13 — Foto e nome do contato

### Confirmar antes
- `get_profile_picture` contra o Swagger da evolution-go: nome do campo dentro
  de `data` (`profilePictureUrl`? `url`?).
- Quais colunas do contato já existem: `foto_perfil` (chave de storage?) e
  `foto_perfil_url_origem`. O P8 grava a segunda.

### Entregáveis
1. **Corrigir o cliente de avatar** (`infrastructure_evolution`): passar pelo
   `json_do_provedor`, aceitando com e sem envelope. O teste de wiremock ganha
   o caso **com** `{data: …}`, que é o real.
2. **Migration 0039:** `oraculo_contato.foto_verificada_em TIMESTAMPTZ`. É o
   freio da busca sob demanda: ninguém consulta o provedor de novo antes de 7
   dias, nem quando a resposta foi "sem foto".
3. **`infrastructure_postgres`:** `foto_do_contato(atendimento_id)` e
   `registrar_foto(contato_id, url | None)`, sem macro.
4. **`data_postgres`:** rotas `FotoDoContato` e `RegistrarFotoDoContato`.
5. **`runtime_api`:** `ObterFotoDoContato(atendimento_id)`:
   - devolve a URL gravada se `foto_verificada_em` tiver menos de 7 dias;
   - senão, pede ao `data_whatsapp` (`GetWhatsappProfilePicture` com a
     instância do atendimento, via `ResolverDestinoDoAtendimento` do P2),
     grava e devolve;
   - o parâmetro `forcar` ignora o prazo **uma vez**. A tela o usa quando a
     imagem vem quebrada (URL do CDN expirada).
6. **Contrato:** `AtendimentoResumo.foto_url` e `contato.foto_url` na ficha,
   preenchidos com o que está gravado. A listagem **nunca** chama o provedor:
   seriam N chamadas por abertura do quadro.
7. **Nome:** quando `nome_contato` está vazio, o cartão e o cabeçalho usam
   `nome_perfil_whatsapp` antes do telefone. Conferir o que o resumo já faz.
8. **Flutter:** `AvatarDoContato` (foto com `errorBuilder` → iniciais; na
   primeira falha chama `ObterFotoDoContato(forcar: true)` uma vez por sessão).
   Usado no cartão, no cabeçalho da conversa e na ficha.

### Observabilidade & Auditoria
- **Logs:** span `contato.foto` com `atendimento_id`, `origem`
  (`cache`/`provedor`/`sem_foto`) e duração. Falha do provedor é `warn`, com
  telefone mascarado.
- **Auditoria:** sem evento de auditoria, de propósito. É enriquecimento
  derivado (decisão da N11 E6).
- **Sanitização:** a URL da foto é assinada e identifica a pessoa: nunca em
  log nem em span.

### DoD
Foto aparece no cartão de um contato que tem foto no WhatsApp. Imagem quebrada
vira iniciais e é renovada uma vez. O provedor é consultado no máximo uma vez
por contato a cada 7 dias. Teste de wiremock com envelope.

---

## P14 — Etiquetagem por intenção (N10 E3)

### Confirmar antes
- O `AnexarAnaliseMensagem` (B9) já grava intenções e o assunto na mesma
  transação; é ali que a etiqueta entra.
- O `AlternarEtiqueta` manual: onde gravar a marca de remoção humana.

### Entregáveis
1. **Migration 0040:**
   - `atu_etiqueta_atendimento.origem VARCHAR(10) NOT NULL DEFAULT 'manual'`
     (`manual` | `ia`); as linhas existentes são manuais, e o default diz isso;
   - `atu_etiqueta_bloqueada (tenant_id, atendimento_id, etiqueta_id,
     bloqueada_em, por_usuario_id)`, com UNIQUE e RLS. É o "removida por humano
     não volta".
2. **Regra de aplicação** (no handler da análise, mesma transação):
   - só intenções com confiança ≥ `confianca_minima_automatica` do tenant (B4:
     um número só para "quando confio na IA");
   - só etiquetas **ativas** que já existem no catálogo, casando nome sem
     diferenciar maiúsculas e acentos. **Nunca cria etiqueta**: o catálogo é
     curadoria do tenant;
   - pula o que estiver em `atu_etiqueta_bloqueada`;
   - `INSERT … ON CONFLICT DO NOTHING` com `origem = 'ia'`.
3. **Remoção manual** (`AlternarEtiqueta` desligando): grava o bloqueio. Vale
   para qualquer remoção humana, venha a etiqueta da IA ou de uma pessoa. Quem
   tirou decidiu, e a IA não reaplica no mesmo atendimento. Religar à mão apaga
   o bloqueio.
4. **Realtime:** o worker publica `atendimento.etiquetas_atualizadas` quando
   aplicou alguma. O quadro já recarrega o cartão pelo `atendimento_id`.
5. **Contrato e tela:** `Etiqueta.origem` na ficha; a etiqueta da IA mostra
   um ícone ✨ com tooltip "aplicada pela IA".

### Observabilidade & Auditoria
- **Logs:** `etiquetas_aplicadas` e `etiquetas_bloqueadas` (contagens) no span
  `ia.analise`.
- **Auditoria:** `etiqueta.aplicada_por_ia` (atendimento, etiqueta,
  confiança; `user_id` nulo), e o bloqueio no evento de remoção já existente,
  com `bloqueou_ia: true`.
- **Sanitização:** nome de etiqueta não é PII.

### DoD
Intenção confiante aplica a etiqueta existente de mesmo nome. Intenção sem
etiqueta no catálogo não cria nada. Etiqueta removida por humano não volta na
mensagem seguinte. Testes de integração dos três casos.

---

## P15 — Enriquecimento do contato (N10 E4)

### Confirmar antes
- Os `tipo`s que o `ia_engine` devolve em `Entidade` com a config
  `entity_types` do tenant (vazio = sem restrição).
- Como `oraculo_contato.nome_contato` é preenchido na ingestão (o `pushName`
  entra por `salvar`): o "vazio" para nome raramente acontece, e isso é o certo.

### Entregáveis
1. **Mapa fechado** tipo → campo: `nome` → `nome_contato`, `email` →
   `email`. Todo o resto vai para `oraculo_contato.metadados.entidades`,
   **somando** às chaves que já existem, nunca substituindo.
2. **Regras duras** (função pura, testada à parte):
   - só preenche campo **vazio** (NULL ou só espaços);
   - confiança ≥ `confianca_minima_automatica`;
   - e-mail com formato válido e até 254 caracteres; nome entre 2 e 100
     caracteres, sem dígitos;
   - no máximo um valor por tipo por mensagem (o de maior confiança).
3. **Onde:** no mesmo handler da análise (P14), na mesma transação, com o
   `contato_id` do atendimento.
4. **Tela:** a ficha mostra "Dados que a IA encontrou" (as entidades de
   `metadados`) em seção recolhida, só para leitura.

### Observabilidade & Auditoria
- **Logs:** contagem `campos_contato_preenchidos`, nunca valores.
- **Auditoria:** `contato.enriquecido_por_ia` com `contato_id` e a **lista de
  campos**. É o que permite desfazer.
- **Sanitização:** nome, e-mail e documento são PII direta: fora de log, span,
  métrica e descrição de auditoria. O teste de auditoria confere que o valor
  não aparece.

### DoD
E-mail dito na conversa entra no cadastro vazio e não substitui um preenchido.
Valor inválido ou de baixa confiança não entra. Auditoria sem valor.

---

## P16 — Acabamentos do quadro

### (a) Esconder ações de quem só lê (B2)
- O `OperacionalModule` recebe `podeAlterar: bool Function(String acao)` do
  app, no mesmo desenho do `usuarioAtual` e do `buscarContatos`: o módulo não
  conhece a sessão.
- Ações condicionadas: enviar mensagem, anexar, gravar áudio, mover, atribuir,
  prioridade, transferir, etiquetas, notas. O quadro abre em leitura.
- O mapa de escopos vem de `permissoes_de_tela.dart` (espelho do
  `rbac::MAPA`, com teste que lê o `rbac.rs`).

### (b) Marca "revisar" no cartão (B4)
- **Migration 0041:** `oraculo_atendimento.revisao_pendente BOOLEAN NOT NULL
  DEFAULT FALSE`.
- O worker marca quando a decisão da resposta é `revisao` (a mesma
  `decisao_da_resposta` do B4) e desmarca quando um atendente envia mensagem ou
  marca como revisado.
- RPC `MarcarRevisado(atendimento_id)`; `AtendimentoResumo.revisao_pendente`;
  chip no cartão e filtro "a revisar" na barra do P1.

### (c) Aviso nativo do Windows (B5)
- `flutter_local_notifications` 22.3.1 (doc local), **só no desktop**, por
  import condicional. No web continua o SnackBar.
- Dispara no evento `atendimento.atribuido` do usuário logado e só quando a
  janela **não** está em foco. Com o app na frente, o aviso do quadro basta.
- O clique abre a conversa (payload `{"atendimento_id": n}`).
- AUMID e GUID fixos no código; o GUID é gerado uma vez e registrado no
  comentário.

### Observabilidade & Auditoria
- **Logs:** contagem `quadro.revisao_pendente` no worker; nenhum log de
  conteúdo no cliente.
- **Auditoria:** `atendimento.revisao_concluida` (quem marcou); esconder
  botões não gera evento.
- **Sanitização:** a notificação leva só o nome do contato e o fluxo, nunca o
  texto da mensagem (o aviso do SO pode aparecer na tela bloqueada).

### DoD
Um `viewer` abre o quadro sem nenhum botão de escrita. Uma resposta abaixo da
confiança automática põe o cartão em "revisar", e a resposta do atendente tira.
A atribuição com o app minimizado aparece no Windows, e o clique abre a
conversa. O build web continua passando.

---

## P17 — Revisão das avaliações do teste (B9, opcional no plano original)

- `ListMyAvaliacoesDeTeste` (filtro "ruins com correção", paginado), com
  escopo `treinamento:read`.
- Ação **"Virar treinamento"**: cria um rascunho de treinamento com a pergunta
  e a resposta correta (`treinamento:write`). O ciclo de sempre segue:
  revisar, finalizar, vetorizar.
- Aba **Avaliações** na tela de treinamento.

### Observabilidade & Auditoria
- **Logs:** contagem por página.
- **Auditoria:** `treinamento.correcao_promovida` (id da avaliação e do
  treinamento).
- **Sanitização:** pergunta e correção podem citar cliente e ficam fora de log.

### DoD
A correção feita no teste vira material de treinamento em dois cliques.

---

## P18 — Fechar o fallback de escopos (D4, passos 2 e 3)

### 🚨 Gate antes de começar
Consultar em **produção**, por pelo menos 14 dias, quantas sessões chegam com
`origem_escopos = fallback_role` (campo do span de login e refresh). O passo 3
só entra quando esse número for zero depois do passo 2. **Mexe em quem já
trabalha:** fechar às cegas derruba acesso.

### Passo 2 — migrar
- Função pura `escopos_do_papel(role)`, extraída do fallback de
  `derivar_escopos` (fonte única, sem cópia em SQL).
- RPC de superusuário `MigrarEscoposImplicitos(dry_run)`: para cada
  `TenantUser` com `module_permissions` vazio, grava os escopos que ele já tem
  hoje pelo papel. Não muda o acesso de ninguém, só o torna explícito.
  `dry_run` devolve a contagem por tenant e papel.
- Botão no painel do superusuário, com a prévia do `dry_run` antes.

### Passo 3 — fechar
- CoreSetting `AUTH_FALLBACK_ROLE_HABILITADO` (padrão `true`). Com `false`,
  sessão sem `module_permissions` recebe só os escopos de leitura. O papel
  somente-leitura do D4 passa a ser o piso real.
- Desligar é decisão do operador, depois do gate.

### Observabilidade & Auditoria
- **Logs:** contagem de migrados por tenant; o `origem_escopos` já existente.
- **Auditoria:** `tenant_user.permissoes_migradas` **por usuário**, com os
  escopos gravados (mudança de permissão é evento crítico, doc 08 §4.2), e
  `core_setting.alterado` ao desligar o fallback.
- **Sanitização:** nenhum token; escopo não é segredo.

### DoD
Depois do passo 2, `fallback_role` some da medição. Desligar o fallback não
muda o acesso de ninguém que estava ativo. O teste confere que
`escopos_do_papel` e o fallback antigo dão o mesmo resultado para todos os
papéis.

---

## Correções aplicadas (em relação aos planos de origem)

| Onde | Estava | Ficou | Por quê / fonte |
|---|---|---|---|
| N11 E6 | "buscar sob demanda" sobre um cliente dado como pronto | Primeiro passo é **corrigir o cliente de avatar** (envelope `{data}`) | O cliente desserializa sem envelope e o teste usa mock sem envelope; memória `evolution-go-contrato` |
| N11 E6 | guardar em `whatsapp_contact.foto_perfil` | guardar em `oraculo_contato` (URL + `foto_verificada_em`) | O P8 já grava a foto do `CONTACTS` em `oraculo_contato`, e é ele que a tela lê. Duas fontes divergiriam. |
| N10 E3 | "limiar de confiança" sem número | `confianca_minima_automatica` do tenant | O B4 fixou um número só para "quando confio na IA" |
| N10 E3 | coluna `origem` com `bot` / `manual` | `ia` / `manual` + tabela de bloqueio | "removida por humano não volta" precisa lembrar a remoção, e uma linha apagada não guarda nada |
| N10 E4 | "estender `UpsertContact` com fill-if-empty" | função no handler da análise, mesma transação | Não existe `UpsertContact` na v2 com esse papel; o `salvar` é o upsert da ingestão, e mudar sua semântica mexeria com o pushName |
| doc 36 B5 | "notificação do sistema operacional" sem lib | `flutter_local_notifications` 22.3.1, só desktop | `local_notifier` está parado há 2 anos e quebra o build web; doc na central |
| regras D4 | passo 2 "migrar" sem forma | RPC com `dry_run` e fonte única da regra | Uma cópia da regra em SQL divergiria do Rust; `dry_run` é o que torna o passo seguro |
| N10 E6.1 | teste com mídia (opcional) | fora deste plano | Sem pedido de uso; decisão registrada |
