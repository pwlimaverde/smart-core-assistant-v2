"""Features do ia_engine (uma por RPC de negócio).

Cada feature segue o padrão py-return-success-or-error:
`domain/` (erros fechados, parâmetros, usecase) ← `datasources/` (I/O bruto)
← `repositories/` (anticorrupção via `map_error`). O `servicer` compõe as
camadas por request e consome `Success`/`Failure` com `match`.
"""
