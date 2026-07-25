"""Wrapper minimo para segredos em memoria (chaves Fernet/AES, senhas de DB).

Evita a dependencia pesada do pydantic apenas por causa do `SecretStr` — a
regra de seguranca (doc do plano, item 5) e "a chave Fernet e a chave AES-GCM
nunca aparecem em log". Este wrapper garante isso por padrao em `__repr__`/
`__str__`, exigindo `.reveal()` explicito para obter o valor real.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Secret:
    """Envelope opaco para uma string sensivel.

    `repr()`/`str()`/f-strings nunca expoem o conteudo — apenas `.reveal()`
    devolve o valor real. Use `.reveal()` no ultimo instante possivel (ex.:
    logo antes de `Fernet(chave)` ou `AESGCM(chave)`), nunca armazene o
    resultado de `.reveal()` em outro lugar que possa ser logado.
    """

    _value: str

    def reveal(self) -> str:
        return self._value

    def __repr__(self) -> str:  # pragma: no cover - trivial
        return "Secret('***REDACTED***')"

    def __str__(self) -> str:  # pragma: no cover - trivial
        return "***REDACTED***"
