# 38 — Cronograma: pendências pós-paridade

> **Origem:** varredura de 2026-09-19 sobre os planos N9–N13, regras do bot,
> painel CRM, doc 36 ("fica de fora") e doc 37 (paridade P1–P12), conferida no
> código — não nos marcadores `status: pending` dos planos antigos.
> **Plano canônico:** `.context/plans/pendencias-pos-paridade.md` (detalhe
> técnico em `.context/plans/pendencias-pos-paridade/`).
> **Branch:** `feat/pendencias-pos-paridade`.
> **Alvo:** o app Windows do tenant.

## Método

O mesmo do doc 37: cada fase fecha um assunto de ponta a ponta (contrato →
migration → `data_postgres` → `runtime_api` → stubs → app → testes). A CI
precisa ficar verde antes da fase seguinte. Testes não rodam nesta máquina.

## Fases

| # | Fase | Origem | Por que nesta posição | Estado |
|---|------|--------|-----------------------|--------|
| P13 | Foto e nome do contato | N11 E6 | Corrige primeiro um defeito latente (envelope `{data}` do avatar), e é o mais visível para quem atende | ⬜ |
| P14 | Etiquetagem por intenção | N10 E3 | Tem a regra de conflito com humano; fixa o padrão que o P15 reusa no mesmo handler | ⬜ |
| P15 | Enriquecimento do contato | N10 E4 | Mesmo handler do P14; é a fase de PII mais sensível | ⬜ |
| P16 | Acabamentos do quadro | doc 36 B2, B4, B5 | Independente; traz a única lib nova (`flutter_local_notifications`) | ⬜ |
| P17 | Revisão das avaliações do teste | doc 36 B9 | Opcional no plano original; barata depois do B9 | ⬜ |
| P18 | Fechar o fallback de escopos | regras D4 | **Por último e com gate**: mexe no acesso de quem já trabalha | ⬜ |

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

## Achados fora do inventário

- **O cliente de avatar da evolution-go ignora o envelope `{data}`**
  (`infrastructure_evolution::get_profile_picture`), e o teste com mock usa a
  resposta sem envelope — contra o servidor real a foto volta sempre vazia.
  Entrou como passo 1 do P13.
