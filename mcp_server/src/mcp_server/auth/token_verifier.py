"""Validação do access token do cliente MCP e troca pelo token interno.

# As duas metades, e por que são separadas

**Verificar** (`VerificadorDeToken`) é local e barato: confere assinatura RS256
com a chave pública, `iss`, `exp` e — o que mais importa — **`aud`**. É o que
roda em toda requisição.

**Trocar** (`trocar_por_token_interno`) é uma chamada ao `control_plane` e só
acontece quando a requisição vai de fato falar com o backend. Ela existe porque
a spec é literal:

    "The MCP server MUST NOT pass through the token it received from the MCP
    client. […] The access token used at the upstream API is a separate token."

Repassar o token do cliente ao `runtime_api` seria confusão de audiência: aquele
token foi emitido para *este* servidor, e o backend não tem como saber se quem o
apresenta é o destinatário legítimo.

# Sobre a chave

Aqui só existe a chave **pública**. Este processo confere tokens; não emite
nenhum. Se ele for comprometido, o atacante consegue ler o que os tokens que
chegam dizem — não fabricar tokens novos para tenants que quiser.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Any

import httpx2 as httpx
import jwt
from loguru import logger
from mcp.server.auth.provider import AccessToken, TokenVerifier


class TokenInvalido(Exception):
    """Token que não passou na verificação. A mensagem NUNCA carrega o token."""


@dataclass(frozen=True)
class IdentidadeMcp:
    """Quem está falando, extraído das claims já validadas."""

    user_id: int
    tenant_id: str
    grant_id: str
    client_id: str
    escopos: list[str]

    @classmethod
    def de_access_token(cls, token: AccessToken) -> IdentidadeMcp:
        claims: dict[str, Any] = token.claims or {}
        return cls(
            user_id=int(claims.get("sub", 0) or 0),
            tenant_id=str(claims.get("tenant_id", "")),
            grant_id=str(claims.get("grant_id", "")),
            client_id=token.client_id,
            escopos=list(token.scopes),
        )


class VerificadorDeToken(TokenVerifier):
    """Implementa o `TokenVerifier` do SDK sobre os nossos JWTs RS256."""

    def __init__(self, chave_publica_pem: str, issuer: str, resource: str) -> None:
        self._chave = chave_publica_pem
        self._issuer = issuer.rstrip("/")
        self._resource = resource.rstrip("/")

    async def verify_token(self, token: str) -> AccessToken | None:
        """Devolve o `AccessToken` do SDK, ou `None` para qualquer recusa.

        O SDK trata `None` como 401 com o `WWW-Authenticate` correto — por isso
        não levantamos exceção aqui. Todo motivo de recusa vai para o log em
        `debug`, sem o token e sem as claims.
        """
        if not self._chave:
            logger.error("chave pública do AS ausente: nenhum token pode ser validado")
            return None

        try:
            claims = jwt.decode(
                token,
                self._chave,
                algorithms=["RS256"],
                # `audience` é o coração da validação: um token emitido para
                # outro recurso é recusado mesmo com assinatura perfeita.
                audience=self._resource,
                issuer=self._issuer,
                options={
                    "require": ["exp", "iss", "aud", "sub"],
                    "verify_exp": True,
                    "verify_aud": True,
                    "verify_iss": True,
                },
            )
        except jwt.InvalidAudienceError:
            # Vale um log próprio: audiência errada não é token expirado, é
            # tentativa de usar credencial de outro serviço aqui.
            logger.warning("token recusado: audiência não é este resource server")
            return None
        except jwt.PyJWTError as exc:
            logger.debug("token recusado: {}", type(exc).__name__)
            return None

        escopos = claims.get("scopes") or []
        if not isinstance(escopos, list):
            logger.debug("token recusado: claim `scopes` malformada")
            return None

        return AccessToken(
            token=token,
            client_id=str(claims.get("client_id", "")),
            scopes=[str(e) for e in escopos],
            expires_at=int(claims["exp"]),
            resource=self._resource,
            subject=str(claims.get("sub", "")),
            claims=claims,
        )


class TrocadorDeToken:
    """Obtém o JWT interno junto ao `control_plane`, com cache curto.

    O cache é por `jti` do token do cliente e expira **antes** do token interno,
    para nunca entregar credencial vencida. Sem ele, um agente ativo faria uma
    chamada HTTP ao `control_plane` por chamada de tool — o dobro de latência em
    troca de nada, já que a resposta seria idêntica durante minutos.
    """

    #: Margem antes do vencimento. Uma chamada gRPC que leve 20s com um token de
    #: 30s restantes ainda precisa chegar válida do outro lado.
    MARGEM_S = 60

    def __init__(
        self, url: str, segredo_de_servico: str, timeout_s: float = 5.0
    ) -> None:
        self._url = url
        self._segredo = segredo_de_servico
        self._timeout = timeout_s
        self._cache: dict[str, tuple[str, float]] = {}

    async def obter(self, access_token: str, jti: str) -> str:
        agora = time.time()
        em_cache = self._cache.get(jti)
        if em_cache and em_cache[1] > agora:
            return em_cache[0]

        async with httpx.AsyncClient(timeout=self._timeout) as cliente:
            resposta = await cliente.post(
                self._url,
                json={"access_token": access_token},
                headers={"X-Servico-Secreto": self._segredo},
            )

        if resposta.status_code != 200:
            # O corpo da resposta pode conter descrição de erro do AS; o token,
            # não. Logamos só o status.
            logger.warning(
                "troca por token interno recusada pelo control_plane (status {})",
                resposta.status_code,
            )
            raise TokenInvalido("credencial não pôde ser trocada por uma interna")

        corpo = resposta.json()
        interno = corpo.get("internal_token", "")
        if not interno:
            raise TokenInvalido("resposta da troca de token sem credencial")

        expira_em = float(corpo.get("expires_in", 300))
        self._cache[jti] = (interno, agora + max(expira_em - self.MARGEM_S, 5))
        self._limpar_expirados(agora)
        return interno

    def _limpar_expirados(self, agora: float) -> None:
        """Poda o cache. Sem isto ele cresceria por `jti`, ou seja, sem limite."""
        vencidos = [k for k, (_, ate) in self._cache.items() if ate <= agora]
        for k in vencidos:
            self._cache.pop(k, None)
