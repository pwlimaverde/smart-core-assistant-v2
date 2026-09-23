# 38 — Cronograma: pendências pós-paridade

> **Origem:** varredura de 2026-09-19 sobre os planos N9–N13, regras do bot,
> painel CRM, doc 36 ("fica de fora") e doc 37 (paridade P1–P12), conferida no
> código — não nos marcadores `status: pending` dos planos antigos.
> **Plano canônico (arquivado em 23/09):**
> `.context/plans/archive/pendencias-pos-paridade/`.
> **Branch:** `feat/pendencias-pos-paridade`.
> **Alvo:** o app Windows do tenant.

## Método

O mesmo do doc 37: cada fase fecha um assunto de ponta a ponta (contrato →
migration → `data_postgres` → `runtime_api` → stubs → app → testes). A CI
precisa ficar verde antes da fase seguinte. Testes não rodam nesta máquina.

## Fases

| # | Fase | Origem | Por que nesta posição | Estado |
|---|------|--------|-----------------------|--------|
| P12b | O app Windows lê do servidor | achado de 22/09 | **Bloqueia o teste prático**: no desktop o quadro, a conversa e o realtime vinham só do índice local, que nada alimentava | ✅ |
| P13 | Foto e nome do contato | N11 E6 | Corrige primeiro um defeito latente (envelope `{data}` do avatar), e é o mais visível para quem atende | ✅ |
| P14 | Etiquetagem por intenção | N10 E3 | Tem a regra de conflito com humano; fixa o padrão que o P15 reusa no mesmo handler | ✅ |
| P15 | Enriquecimento do contato | N10 E4 | Mesmo handler do P14; é a fase de PII mais sensível | ✅ |
| P16 | Acabamentos do quadro | doc 36 B2, B4, B5 | Independente; traz a única lib nova (`flutter_local_notifications`) | ✅ |
| P17 | Revisão das avaliações do teste | doc 36 B9 | Opcional no plano original; barata depois do B9 | ✅ |
| P18 | Fechar o fallback de escopos | regras D4 | **Por último e com gate**: mexe no acesso de quem já trabalha | ✅ |

**Fora deste cronograma:** N12 (cutover de produção, operação com janela) e o
teste de resposta com mídia (N10 E6.1, opcional, sem pedido de uso).

## Gate do P18

Antes do passo 3 (desligar o fallback), consultar em produção, por pelo menos
14 dias, as sessões com `origem_escopos = fallback_role`. O passo 2 (migrar
para permissões explícitas, com `dry_run`) pode entrar antes; o 3 só com o
número em zero.

## Andamento

| Fase | Commit | CI | O que entrou |
|---|---|---|---|
| P12b | `0d5b449` | 35798247653 ✅ | `LocalEngineGateway` lê do servidor; índice SQLite vira cache e fallback sem rede (SocketException, timeout, `unavailable`); stream mescla remoto + local |
| P13 | `e1724dc` `68af95d` `0271e24` | 35800431668 ✅ | Avatar da evolution-go pelo `json_do_provedor`; migration 0039 (`foto_verificada_em`); `ObterContatoDoAtendimento` com freio de 7 dias e `forcar` (≥10 min); nome/telefone/foto no resumo; `AvatarDoContato` no cartão e no cabeçalho |
| P14 | `e9654dc` `907539c` `499d582` | 35801720073 ✅ | Migration 0040 (`origem` + `atu_etiqueta_bloqueada` com RLS); IA aplica etiqueta pela intenção acima do piso; o que humano removeu não volta; auditoria `etiqueta.aplicada_por_ia`; ✨ no chip |
| P15 | `f8b4539` `84009c2` `2f77ca0` | 35801735996 ✅ | Enriquecimento só de campo vazio, com confiança mínima; auditoria `contato.enriquecido_por_ia` sem valor; "Dados que a IA encontrou" na ficha. `map<>` trocado por `repeated DadoDoContato` (o conversor proto→flatbuffers não aceita map) |
| P16 | `5253370` | 35801745608 ✅ | Migration 0041 (`revisao_pendente`); quadro só-leitura para quem não atende; filtro "A revisar" + `MarcarRevisado`; aviso nativo do Windows (`flutter_local_notifications` 22.3.1) |
| P17 | `367bbb6` | 35801750976 ✅ | Migration 0042 (`tratada_em`); aba "Avaliações" no treinamento: a correção vira material pela criação normal ou é dispensada, com auditoria |
| P18 | `1241c89` | 35801756123 ✅ | `escopos_do_papel` como fonte única (teste confere igualdade com o fallback para todo papel); `MigrarEscoposImplicitos(dry_run)` do superusuário com gravação condicional e auditoria `tenant_user.permissoes_migradas` por usuário; CoreSetting `AUTH_FALLBACK_ROLE_HABILITADO` (ausente = habilitado); botão com prévia em Usuários |

**Gate do P18 continua valendo:** o código do passo 3 está pronto, mas a chave
só deve ir para `false` depois de 14 dias de `origem_escopos = fallback_role`
em zero na produção (rodar a migração antes).

**Piso de cobertura Flutter:** P13, P14, P15 e P17 bateram em 77,7–77,96% com
o piso em 78%. Resolvido cobrindo o `AtendimentoRemoteGateway` (177 linhas
descobertas) em vez de baixar o piso.

## Achados fora do inventário

- **O cliente de avatar da evolution-go ignora o envelope `{data}`**
  (`infrastructure_evolution::get_profile_picture`), e o teste com mock usa a
  resposta sem envelope — contra o servidor real a foto volta sempre vazia.
  Entrou como passo 1 do P13.
- **O app Windows não lia do servidor** (22/09). O `LocalEngineGateway` servia
  quadro, conversa e realtime só do índice SQLite local, e nada chamava
  `ingestAtendimento`/`ingestMensagem`: o quadro dependia do que o próprio
  aparelho tinha movido, e nada do P1–P12 (contato, não lidas, ticks, citação,
  reações, presença, atribuição) chegava à tela do Windows. Virou a fase P12b,
  antes do P13: servidor primeiro, índice como cache e fallback sem rede.
- **O cartão do quadro mostra `Contato #id`**: o resumo nunca levou nome nem
  telefone do contato. Entrou no P13.
