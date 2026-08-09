# Collaboration Plans

This directory contains plans for coordinating work across documentation and playbooks.

## Plan Queue

Backlog derivado da **auditoria de código v1 × v2** de 2026-08-08/09
(`doc_dev/planejamento/26-levantamento-paridade-v1-v2.md` e
`27-mapa-telas-rotas-v2.md`). **Ordem de execução:**

1. ~~N8.5 Defeitos do Pipeline~~ — ✅ **concluído** em 2026-08-09
   (ver `archive/n85-defeitos-pipeline/`). Corrigiu as cinco divergências de
   comportamento: grupo virando atendimento, buffer de agregação, pesquisa de
   satisfação, `msg_fallback`, evento `CONNECTION` sem consumidor.
2. **[N9 Conversa Completa](./n9-conversa-completa.md)** — 🚧 **próximo**.
   Caminho crítico: mídia, leitura, presença, citação, busca e ficha.
3. [N10 IA Analítica](./n10-ia-analitica.md) — ligar o `Analyse`, assunto e
   etiqueta automáticos, treinamento por arquivo. Paralelizável com N11.
4. [N11 Operação e Cadastros](./n11-operacao-cadastros.md) — conexões, roteamento
   por instância, whitelist, contatos/PJ, e-mail transacional.
5. [N12 Cutover de Produção](./n12-cutover-producao.md) — ETL, enforce, virada de
   rota e desligamento do legado. Exige as anteriores fechadas.

Cada plano tem pasta própria com o **plano completo** (verdade técnica), o
**`info_aux`** (libs e serviços, com documentação verificada) e, quando houver,
as referências brutas coletadas.

## Concluídos (ver `archive/`)
- N6 Ia Fluxo Vivo · N7 Endurecimento Residual · N8 Migração e Cutover
  (código; a execução real é a N12) · **N8.5 Defeitos do Pipeline**

## How To Create Or Update Plans
- Run "dotcontext plan <name>" to scaffold a new plan template.
- Run "dotcontext plan <name> --fill" to have an LLM refresh the plan using the latest repository context.

## Related Resources
- [Agent Handbook](../agents/README.md)
- [Documentation Index](../docs/README.md)
- [Agent Knowledge Base](../../AGENTS.md)
- [Contributor Guidelines](../../CONTRIBUTING.md)
