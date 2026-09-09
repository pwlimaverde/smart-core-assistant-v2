"""Validação do access token — com chaves RSA de verdade.

Gerar um par de chaves no teste custa pouco e vale muito: exercita o caminho
real de assinatura/verificação em vez de um mock que diria "ok" para tudo.

O teste que mais importa é `token_de_audiencia_alheia_e_recusado`. Ele é a
defesa contra confusão de audiência: um token emitido para outro serviço nosso,
com assinatura perfeita e não expirado, **não** pode valer aqui.
"""

from __future__ import annotations

import time

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from mcp_server.auth.token_verifier import IdentidadeMcp, VerificadorDeToken

ISSUER = "https://auth.smartcoreassistant.com.br"
RESOURCE = "https://mcp.smartcoreassistant.com.br"


@pytest.fixture(scope="module")
def chaves() -> tuple[str, str]:
    chave = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    privada = chave.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    publica = (
        chave.public_key()
        .public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo,
        )
        .decode()
    )
    return privada, publica


def emitir(privada: str, **sobrescreve: object) -> str:
    agora = int(time.time())
    claims: dict[str, object] = {
        "iss": ISSUER,
        "sub": "7",
        "aud": RESOURCE,
        "exp": agora + 900,
        "iat": agora,
        "jti": "jti-1",
        "tenant_id": "11111111-1111-1111-1111-111111111111",
        "scopes": ["atendimentos:read"],
        "grant_id": "grant-1",
        "client_id": "https://claude.ai/mcp-client",
    }
    claims.update(sobrescreve)
    return jwt.encode(claims, privada, algorithm="RS256")


@pytest.fixture
def verificador(chaves) -> VerificadorDeToken:
    _, publica = chaves
    return VerificadorDeToken(publica, ISSUER, RESOURCE)


async def test_token_valido_e_aceito_com_as_claims(verificador, chaves):
    privada, _ = chaves
    token = await verificador.verify_token(emitir(privada))

    assert token is not None
    assert token.scopes == ["atendimentos:read"]
    identidade = IdentidadeMcp.de_access_token(token)
    assert identidade.user_id == 7
    assert identidade.grant_id == "grant-1"
    assert identidade.tenant_id == "11111111-1111-1111-1111-111111111111"


async def test_token_de_audiencia_alheia_e_recusado(verificador, chaves):
    """Assinatura perfeita, não expirado, emissor certo — e ainda assim recusado.

    É a defesa contra reaproveitar aqui um token emitido para outro serviço.
    """
    privada, _ = chaves
    token = emitir(privada, aud="https://outro-servico.smartcoreassistant.com.br")
    assert await verificador.verify_token(token) is None


async def test_token_de_outro_emissor_e_recusado(verificador, chaves):
    privada, _ = chaves
    assert (
        await verificador.verify_token(emitir(privada, iss="https://mau.example"))
        is None
    )


async def test_token_expirado_e_recusado(verificador, chaves):
    privada, _ = chaves
    agora = int(time.time())
    token = emitir(privada, exp=agora - 10, iat=agora - 1000)
    assert await verificador.verify_token(token) is None


async def test_token_assinado_por_outra_chave_e_recusado(verificador):
    outra = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = outra.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode()
    assert await verificador.verify_token(emitir(pem)) is None


async def test_token_sem_assinatura_e_recusado(verificador, chaves):
    """`alg: none` é o ataque clássico contra validador mal configurado."""
    agora = int(time.time())
    token = jwt.encode(
        {"iss": ISSUER, "sub": "7", "aud": RESOURCE, "exp": agora + 900},
        key="",
        algorithm="none",
    )
    assert await verificador.verify_token(token) is None


async def test_token_sem_claims_obrigatorias_e_recusado(chaves):
    privada, publica = chaves
    verificador = VerificadorDeToken(publica, ISSUER, RESOURCE)
    agora = int(time.time())
    # Sem `sub`: não dá para saber quem é o usuário.
    token = jwt.encode(
        {"iss": ISSUER, "aud": RESOURCE, "exp": agora + 900},
        privada,
        algorithm="RS256",
    )
    assert await verificador.verify_token(token) is None


async def test_sem_chave_publica_nenhum_token_passa(chaves):
    """Falha fechada: servidor mal configurado recusa tudo, não aceita tudo."""
    privada, _ = chaves
    verificador = VerificadorDeToken("", ISSUER, RESOURCE)
    assert await verificador.verify_token(emitir(privada)) is None


async def test_claim_scopes_malformada_e_recusada(verificador, chaves):
    privada, _ = chaves
    token = emitir(privada, scopes="atendimentos:read")  # string, não lista
    assert await verificador.verify_token(token) is None
